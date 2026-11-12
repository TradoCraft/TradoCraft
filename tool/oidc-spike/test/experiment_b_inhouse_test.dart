// Experiment B: the in-house flow against the same Keycloak, same fake browser.
// Run: flutter test test/experiment_b_inhouse_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:oidc_spike/fake_browser.dart';
import 'package:oidc_spike/inhouse_oidc.dart';
import 'package:oidc_spike/keycloak_admin.dart';
import 'package:test/test.dart';

const cfg = OidcConfig(issuer: kIssuer, clientId: kClientId);

/// Counts calls to the token endpoint.
class CountingInterceptor extends Interceptor {
  int tokenCalls = 0;
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    if (o.uri.path.endsWith('/token')) tokenCalls++;
    h.next(o);
  }
}

Future<void> Function(Uri) drive(FakeBrowser b, {List<Uri>? shown}) =>
    (u) async {
      shown?.add(u);
      unawaited(b.login(u).catchError((Object e) => 'browser error: $e'));
    };

void main() {
  test('B0 PKCE: RFC 7636 appendix B vector', () {
    final p = Pkce.fromVerifier('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk');
    expect(p.challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    final g = Pkce.generate();
    expect(g.verifier.length, 43);
    expect(RegExp(r'^[A-Za-z0-9\-._~]{43}$').hasMatch(g.verifier), isTrue);
  });

  test('B1 login with code+PKCE through the loopback listener', () async {
    final b = FakeBrowser();
    final c = InHouseOidcClient(cfg, MemoryTokenStore());
    final t = await c.signIn(present: drive(b));
    final at = jwtClaims(t.accessToken);
    final id = jwtClaims(t.idToken!);
    print('B1 callback to ${b.callbackUris.single.replace(query: '')}');
    print(
      'B1 access token iss=${at['iss']} aud=${at['aud']} sub=${at['sub']}; '
      'id token email=${id['email']} email_verified=${id['email_verified']} nonce checked',
    );
    expect(at['aud'], contains(kClientId));
    expect(t.refreshToken, isNotNull);
  });

  test('B2 refresh twice, rotation, single-flight', () async {
    final b = FakeBrowser();
    final counter = CountingInterceptor();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(counter);
    final store = MemoryTokenStore();
    final c = InHouseOidcClient(cfg, store, dio: dio);
    final t0 = await c.signIn(present: drive(b));
    final t1 = await c.refresh();
    final t2 = await c.refresh();
    print(
      'B2 AT changed=${t1.accessToken != t0.accessToken} RT rotated #1=${t1.refreshToken != t0.refreshToken} #2=${t2.refreshToken != t1.refreshToken}; store holds newest=${store.value!.refreshToken == t2.refreshToken}',
    );
    final before = counter.tokenCalls;
    final tokens = await Future.wait(
      List.generate(
        8,
        (_) => c.accessToken(minValidity: const Duration(seconds: 120)),
      ),
    );
    print(
      'B2 8 concurrent accessToken(120s): distinct=${tokens.toSet().length} token calls=${counter.tokenCalls - before}',
    );
    expect(counter.tokenCalls - before, 1);
  });

  test(
    'B3 revoked refresh token -> SignedOutException, store cleared',
    () async {
      final b = FakeBrowser();
      final admin = KeycloakAdmin();
      final store = MemoryTokenStore();
      final c = InHouseOidcClient(cfg, store);
      await c.signIn(present: drive(b));
      await admin.revokeOfflineTokens(await admin.userId('alice'));
      Object? err;
      try {
        await c.refresh();
      } catch (e) {
        err = e;
      }
      print('B3 after revoke -> $err; store cleared=${store.value == null}');
      expect(err, isA<SignedOutException>());
      admin.close();
    },
  );

  test('B4 network error is transient and keeps the session', () async {
    final b = FakeBrowser();
    final store = MemoryTokenStore();
    final failing = Dio(BaseOptions(validateStatus: (_) => true));
    final c0 = InHouseOidcClient(cfg, store);
    await c0.signIn(present: drive(b));
    failing.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (o.uri.path.endsWith('/token')) {
            return h.reject(
              DioException.connectionError(
                requestOptions: o,
                reason: 'offline',
              ),
            );
          }
          h.next(o);
        },
      ),
    );
    final c = InHouseOidcClient(cfg, store, dio: failing);
    Object? err;
    try {
      await c.refresh();
    } catch (e) {
      err = e.runtimeType;
    }
    print('B4 offline refresh -> $err; session kept=${store.value != null}');
    expect(err, TransientAuthException);
    expect(store.value, isNotNull);
  });

  test('B5 logout: local delete first, revoke, end_session URL, RT dead', () async {
    final b = FakeBrowser();
    final store = MemoryTokenStore();
    final c = InHouseOidcClient(cfg, store);
    final t = await c.signIn(present: drive(b));
    final rt = t.refreshToken!;
    final end = await c.signOut();
    print(
      'B5 store cleared=${store.value == null}; end_session params=${end!.queryParameters.keys.toList()}',
    );
    final page = await b.visit(end);
    print(
      'B5 end_session page shows logged out/confirm: ${page.contains('kc-logout') || page.toLowerCase().contains('logout') || page.toLowerCase().contains('signed out')}',
    );
    final c2 = InHouseOidcClient(
      cfg,
      MemoryTokenStore()
        ..value = Tokens(
          accessToken: 'x',
          expiresAt: DateTime(2000),
          refreshToken: rt,
        ),
    );
    Object? err;
    try {
      await c2.refresh();
    } catch (e) {
      err = e;
    }
    print('B5 refresh with pre-logout RT -> $err');
  });

  test('B6 port-agnostic redirect and no-browser behaviour', () async {
    final ports = <int>{};
    for (var i = 0; i < 3; i++) {
      final b = FakeBrowser();
      await InHouseOidcClient(
        cfg,
        MemoryTokenStore(),
      ).signIn(present: drive(b));
      ports.add(b.callbackUris.single.port);
    }
    print('B6 loopback ports used: $ports');
    // No browser: present() publishes the URL; user opens it elsewhere.
    final b = FakeBrowser();
    final shown = <Uri>[];
    final t = await InHouseOidcClient(
      cfg,
      MemoryTokenStore(),
    ).signIn(present: drive(b, shown: shown));
    print(
      'B6 URL surfaced to UI then completed elsewhere: ${shown.length == 1 && t.accessToken.isNotEmpty}',
    );
    // Cancel while waiting.
    final c = InHouseOidcClient(cfg, MemoryTokenStore());
    final f = c.signIn(
      present: (_) => Future<void>.delayed(
        const Duration(milliseconds: 200),
        c.cancelSignIn,
      ),
    );
    Object? err;
    try {
      await f;
    } catch (e) {
      err = e;
    }
    print('B6 cancel while waiting -> $err');
    // Timeout.
    final c3 = InHouseOidcClient(
      const OidcConfig(
        issuer: kIssuer,
        clientId: kClientId,
        signInTimeout: Duration(seconds: 2),
      ),
      MemoryTokenStore(),
    );
    Object? err3;
    try {
      await c3.signIn(present: (_) {});
    } catch (e) {
      err3 = e;
    }
    print('B6 timeout -> $err3');
    expect(ports.length, greaterThan(1));
  });

  test('B7 two environments, two clients, independent sessions', () async {
    final s1 = MemoryTokenStore(), s2 = MemoryTokenStore();
    final c1 = InHouseOidcClient(cfg, s1), c2 = InHouseOidcClient(cfg, s2);
    await c1.signIn(present: drive(FakeBrowser()));
    await c2.signIn(present: drive(FakeBrowser()));
    print(
      'B7 independent sessions: ${s1.value!.refreshToken != s2.value!.refreshToken}',
    );
  });
}
