import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Keycloak test realm settings (see docker-compose.yml / realm-tradocraft.json).
const kIssuer = 'http://127.0.0.1:18080/realms/tradocraft';
const kClientId = 'tradocraft-app';

/// Acts as the user's browser: opens the authorization URL, submits the login
/// form (cookie jar included) and follows redirects until one points at a
/// loopback listener, which it then GETs, exactly like a real browser would.
class FakeBrowser {
  final HttpClient _http = HttpClient();
  final Map<String, String> _cookies = {};
  final List<String> trace = [];

  /// Redirect URIs (with ports) the browser was sent to, for assertions.
  final List<Uri> callbackUris = [];

  /// Full login: GET the auth URL, post credentials, deliver the callback.
  /// Returns the body the loopback listener answered with.
  Future<String> login(
    Uri authUrl, {
    String user = 'alice',
    String password = 'alice-pass',
  }) async {
    // Walk redirects manually so we stop when the target is a loopback URL
    // that is not Keycloak itself.
    final page = await _walk(authUrl);
    if (page.callback != null) return _deliver(page.callback!);
    final action =
        RegExp(r'<form[^>]*id="kc-form-login"[^>]*action="([^"]+)"')
            .firstMatch(page.body) ??
        RegExp(r'action="([^"]+)"[^>]*id="kc-form-login"')
            .firstMatch(page.body);
    if (action == null) {
      throw StateError('no login form in page: ${page.body.substring(0, 300)}');
    }
    final url = Uri.parse(action.group(1)!.replaceAll('&amp;', '&'));
    final after = await _walk(
      url,
      form: {'username': user, 'password': password, 'credentialId': ''},
    );
    if (after.callback == null) {
      throw StateError(
        'login did not redirect to a callback: ${after.body} trace=$trace',
      );
    }
    return _deliver(after.callback!);
  }

  /// Follows a redirect chain until a Location leaves Keycloak (port != 18080).
  Future<({String body, Uri? callback})> _walk(
    Uri start, {
    Map<String, String>? form,
  }) async {
    var current = start;
    var m = form == null ? 'GET' : 'POST';
    var body = form;
    for (var i = 0; i < 15; i++) {
      final req = await _http.openUrl(m, current);
      req.followRedirects = false;
      if (_cookies.isNotEmpty) {
        req.headers.set(
          'cookie',
          _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        );
      }
      if (body != null) {
        req.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        req.write(Uri(queryParameters: body).query);
      }
      final res = await req.close();
      for (final c in res.cookies) {
        _cookies[c.name] = c.value;
      }
      final text = await utf8.decoder.bind(res).join();
      trace.add('$m ${current.replace(query: '')} -> ${res.statusCode}');
      if (res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.value('location') != null) {
        final next = current.resolve(res.headers.value('location')!);
        if (next.port != 18080) {
          callbackUris.add(next);
          return (body: text, callback: next);
        }
        current = next;
        m = 'GET';
        body = null;
        continue;
      }
      return (body: text, callback: null);
    }
    throw StateError('too many redirects');
  }

  Future<String> _deliver(Uri callback) async {
    final req = await _http.getUrl(callback);
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    trace.add(
      'GET loopback ${callback.replace(query: '')} -> ${res.statusCode}',
    );
    return text;
  }

  /// Opens a URL that is expected to show a page or redirect to a loopback URL
  /// (used for RP-initiated logout).
  Future<String> visit(Uri url) async {
    final r = await _walk(url);
    if (r.callback != null) return _deliver(r.callback!);
    return r.body;
  }

  void close() => _http.close(force: true);
}

/// Decodes the payload of a JWT without verifying it (test inspection only).
Map<String, dynamic> jwtClaims(String jwt) {
  final p = jwt.split('.')[1];
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(p))))
      as Map<String, dynamic>;
}

/// http.Client that records every request/response (bodies truncated), so the
/// experiments can show what the library sends to the token endpoint.
class LoggingClient extends http.BaseClient {
  LoggingClient({this.verbose = false});
  final bool verbose;
  final http.Client _inner = http.Client();
  final List<String> log = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    final bytes = await res.stream.toBytes();
    final body = utf8.decode(bytes, allowMalformed: true);
    final line = '${request.method} ${request.url.path} -> ${res.statusCode}';
    log.add(line);
    if (verbose || res.statusCode >= 400) {
      final reqBody = request is http.Request ? request.body : '';
      print(
        'HTTP $line req=${reqBody.length > 300 ? reqBody.substring(0, 300) : reqBody} '
        'res=${body.length > 300 ? body.substring(0, 300) : body}',
      );
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      res.statusCode,
      headers: res.headers,
      request: request,
      reasonPhrase: res.reasonPhrase,
      contentLength: bytes.length,
    );
  }
}
