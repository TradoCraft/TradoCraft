// Experiment B: minimal in-house OIDC public-client flow (authorization code +
// PKCE with a loopback listener, refresh with rotation, single-flight refresh,
// RP-initiated logout, revocation). Pure Dart + dio + crypto, no Flutter.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

// ---------------------------------------------------------------- errors

/// The refresh token is dead (invalid_grant / interaction_required / ...):
/// the user must sign in again. Maps to "signed out for this environment".
class SignedOutException implements Exception {
  SignedOutException(this.code, [this.description]);
  final String code;
  final String? description;
  @override
  String toString() =>
      'SignedOutException($code${description == null ? '' : ': $description'})';
}

/// Network/5xx problem: keep the session, retry with backoff.
class TransientAuthException implements Exception {
  TransientAuthException(this.cause);
  final Object cause;
  @override
  String toString() => 'TransientAuthException($cause)';
}

/// The interactive flow failed (denied, state mismatch, timeout, cancelled).
class SignInException implements Exception {
  SignInException(this.message);
  final String message;
  @override
  String toString() => 'SignInException($message)';
}

// ---------------------------------------------------------------- PKCE

class Pkce {
  Pkce._(this.verifier, this.challenge);
  final String verifier;
  final String challenge;

  /// RFC 7636 section 4: 32 random octets -> 43 character verifier.
  factory Pkce.generate([Random? random]) {
    final r = random ?? Random.secure();
    return Pkce.fromVerifier(
      _b64(List<int>.generate(32, (_) => r.nextInt(256))),
    );
  }

  factory Pkce.fromVerifier(String verifier) =>
      Pkce._(verifier, _b64(sha256.convert(ascii.encode(verifier)).bytes));
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String randomToken([int bytes = 24]) {
  final r = Random.secure();
  return _b64(List<int>.generate(bytes, (_) => r.nextInt(256)));
}

Map<String, dynamic> decodeJwtClaims(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) throw SignInException('malformed JWT');
  return jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
  ) as Map<String, dynamic>;
}

// ---------------------------------------------------------------- model

class Tokens {
  Tokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.idToken,
  });
  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;
  final String? idToken;

  Tokens copyWith({String? refreshToken}) => Tokens(
    accessToken: accessToken,
    expiresAt: expiresAt,
    refreshToken: refreshToken ?? this.refreshToken,
    idToken: idToken,
  );
}

/// Where the session lives (secure storage in the app; memory in tests).
abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}

class MemoryTokenStore implements TokenStore {
  Tokens? value;
  @override
  Future<Tokens?> read() async => value;
  @override
  Future<void> write(Tokens tokens) async => value = tokens;
  @override
  Future<void> clear() async => value = null;
}

// ---------------------------------------------------------------- loopback

/// Listens once on 127.0.0.1:<random port> for the redirect.
class LoopbackListener {
  LoopbackListener._(this._server, this.path);
  final HttpServer _server;
  final String path;
  final _result = Completer<Uri>();

  int get port => _server.port;
  Uri get redirectUri =>
      Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path);
  Future<Uri> get result => _result.future;

  static const donePage =
      '<!doctype html><html><head><meta charset="utf-8">'
      '<title>Signed in</title></head><body style="font-family:sans-serif;'
      'text-align:center;margin-top:20vh"><h1>Signed in</h1>'
      '<p>You can close this tab and return to the app.</p></body></html>';

  static Future<LoopbackListener> start({String path = '/callback'}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final l = LoopbackListener._(server, path);
    server.listen((req) async {
      if (req.method == 'GET' &&
          req.uri.path == path &&
          !l._result.isCompleted) {
        req.response
          ..headers.contentType = ContentType.html
          ..write(donePage);
        await req.response.close();
        l._result.complete(
          req.uri.replace(scheme: 'http', host: '127.0.0.1', port: l.port),
        );
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    });
    return l;
  }

  Future<void> close() => _server.close(force: true);
  void cancel(String why) {
    if (!_result.isCompleted) _result.completeError(SignInException(why));
  }
}

// ---------------------------------------------------------------- client

class OidcConfig {
  const OidcConfig({
    required this.issuer,
    required this.clientId,
    this.scopes = const ['openid', 'profile', 'email', 'offline_access'],
    this.refreshSkew = const Duration(seconds: 120),
    this.signInTimeout = const Duration(minutes: 5),
  });
  final String issuer;
  final String clientId;
  final List<String> scopes;
  final Duration refreshSkew;
  final Duration signInTimeout;
}

class InHouseOidcClient {
  InHouseOidcClient(
    this.config,
    this.store, {
    Dio? dio,
    DateTime Function()? now,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 10),
               validateStatus: (_) => true,
             ),
           ),
       _now = now ?? DateTime.now;

  final OidcConfig config;
  final TokenStore store;
  final Dio _dio;
  final DateTime Function() _now;
  Map<String, dynamic>? _meta;
  Future<Tokens>? _refreshing;
  LoopbackListener? _pending;

  Future<Map<String, dynamic>> _discovery() async {
    if (_meta != null) return _meta!;
    final res = await _get('${config.issuer}/.well-known/openid-configuration');
    final meta = res as Map<String, dynamic>;
    if (meta['issuer'] != config.issuer) {
      throw SignInException('discovery issuer mismatch: ${meta['issuer']}');
    }
    return _meta = meta;
  }

  Future<Object?> _get(String url) async {
    try {
      final r = await _dio.get<Object?>(url);
      if ((r.statusCode ?? 500) >= 400)
        throw TransientAuthException('GET $url -> ${r.statusCode}');
      return r.data;
    } on DioException catch (e) {
      throw TransientAuthException(e);
    }
  }

  /// Interactive sign-in. [present] receives the authorization URL; the app
  /// opens it in the system browser, or shows it as copyable text when no
  /// browser can be opened. The flow keeps waiting until the redirect arrives,
  /// [cancelSignIn] is called or the timeout elapses.
  Future<Tokens> signIn({
    required FutureOr<void> Function(Uri url) present,
  }) async {
    final meta = await _discovery();
    final pkce = Pkce.generate();
    final state = randomToken();
    final nonce = randomToken();
    final listener = _pending = await LoopbackListener.start();
    try {
      final url = Uri.parse(meta['authorization_endpoint'] as String).replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': config.clientId,
          'redirect_uri': listener.redirectUri.toString(),
          'scope': config.scopes.join(' '),
          'state': state,
          'nonce': nonce,
          'code_challenge': pkce.challenge,
          'code_challenge_method': 'S256',
        },
      );
      await present(url);
      final cb = await listener.result.timeout(
        config.signInTimeout,
        onTimeout: () =>
            throw SignInException('timed out waiting for the browser'),
      );
      final q = cb.queryParameters;
      if (q['state'] != state) throw SignInException('state mismatch');
      if (q['error'] != null)
        throw SignInException('${q['error']}: ${q['error_description']}');
      if (meta['authorization_response_iss_parameter_supported'] == true &&
          q['iss'] != config.issuer) {
        throw SignInException(
          'iss mismatch in authorization response (RFC 9207)',
        );
      }
      final code = q['code'] ?? (throw SignInException('no code in response'));
      final tokens = await _tokenRequest({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': listener.redirectUri.toString(),
        'code_verifier': pkce.verifier,
      }, expectedNonce: nonce);
      await store.write(tokens);
      return tokens;
    } finally {
      _pending = null;
      await listener.close();
    }
  }

  void cancelSignIn() => _pending?.cancel('cancelled by user');

  /// A token valid for at least [minValidity]; concurrent callers share one
  /// refresh. The rotated refresh token is persisted BEFORE the new access
  /// token is handed out.
  Future<String> accessToken({Duration? minValidity}) async {
    final t = await store.read() ?? (throw SignedOutException('no_session'));
    final need = _now().add(minValidity ?? config.refreshSkew);
    if (t.expiresAt.isAfter(need)) return t.accessToken;
    return (await refresh()).accessToken;
  }

  Future<Tokens> refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<Tokens> _doRefresh() async {
    final current = await store.read();
    final rt =
        current?.refreshToken ?? (throw SignedOutException('no_refresh_token'));
    try {
      final t = await _tokenRequest({
        'grant_type': 'refresh_token',
        'refresh_token': rt,
      });
      // Providers without rotation omit the field: keep the old one.
      final next = Tokens(
        accessToken: t.accessToken,
        expiresAt: t.expiresAt,
        refreshToken: t.refreshToken ?? rt,
        idToken: t.idToken ?? current!.idToken,
      );
      await store.write(next);
      return next;
    } on SignedOutException {
      await store.clear();
      rethrow;
    }
  }

  Future<Tokens> _tokenRequest(
    Map<String, String> form, {
    String? expectedNonce,
  }) async {
    final meta = await _discovery();
    final Response<Object?> res;
    try {
      res = await _dio.post<Object?>(
        meta['token_endpoint'] as String,
        data: {...form, 'client_id': config.clientId},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      throw TransientAuthException(e);
    }
    final status = res.statusCode ?? 500;
    final body = res.data is Map
        ? res.data as Map<String, dynamic>
        : <String, dynamic>{};
    if (status >= 500) throw TransientAuthException('token endpoint $status');
    if (status >= 400) {
      final code = body['error'] as String? ?? 'http_$status';
      const dead = {
        'invalid_grant',
        'interaction_required',
        'login_required',
        'consent_required',
        'unauthorized_client',
      };
      if (dead.contains(code) && form['grant_type'] == 'refresh_token') {
        throw SignedOutException(code, body['error_description'] as String?);
      }
      throw SignInException('$code: ${body['error_description']}');
    }
    final idToken = body['id_token'] as String?;
    if (idToken != null) _checkIdToken(idToken, expectedNonce);
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 300;
    return Tokens(
      accessToken: body['access_token'] as String,
      expiresAt: _now().add(Duration(seconds: expiresIn)),
      refreshToken: body['refresh_token'] as String?,
      idToken: idToken,
    );
  }

  /// The ID token arrives straight from the token endpoint over TLS, so its
  /// signature need not be verified here (OIDC Core 3.1.3.7 item 6); the
  /// claims are still checked. The API server verifies signatures itself.
  void _checkIdToken(String jwt, String? nonce) {
    final c = decodeJwtClaims(jwt);
    final aud = c['aud'];
    if (c['iss'] != config.issuer)
      throw SignInException('id token iss mismatch');
    if (!(aud is List
        ? aud.contains(config.clientId)
        : aud == config.clientId)) {
      throw SignInException('id token aud mismatch');
    }
    if (nonce != null && c['nonce'] != nonce)
      throw SignInException('nonce mismatch');
    final exp = DateTime.fromMillisecondsSinceEpoch((c['exp'] as int) * 1000);
    if (exp.isBefore(_now().subtract(const Duration(seconds: 60)))) {
      throw SignInException('id token expired');
    }
  }

  /// Logout: local tokens are deleted FIRST, then the refresh token is
  /// revoked (RFC 7009) and the end-session URL is built for the browser.
  /// Returns the end-session URL (or null if the provider has none).
  Future<Uri?> signOut() async {
    final t = await store.read();
    await store.clear();
    if (t == null) return null;
    final meta = await _discovery();
    final rev = meta['revocation_endpoint'] as String?;
    if (rev != null && t.refreshToken != null) {
      try {
        await _dio.post<Object?>(
          rev,
          data: {
            'token': t.refreshToken,
            'token_type_hint': 'refresh_token',
            'client_id': config.clientId,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      } on DioException {
        // best effort
      }
    }
    final end = meta['end_session_endpoint'] as String?;
    if (end == null) return null;
    return Uri.parse(end).replace(
      queryParameters: {
        if (t.idToken != null) 'id_token_hint': t.idToken!,
        'client_id': config.clientId,
      },
    );
  }
}
