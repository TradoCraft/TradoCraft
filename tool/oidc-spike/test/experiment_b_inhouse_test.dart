// Experiment B: the in-house flow against the same Keycloak, same fake browser.
// Run: flutter test test/experiment_b_inhouse_test.dart
import 'dart:async';
import 'dart:io';

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

/// Presenter that only records the URL (for tests that deliver manually).
class Recorder {
  final List<Uri> urls = [];
  Future<void> call(Uri u) async => urls.add(u);
}

/// Signs in with [b] acting as the user and returns the tokens. Browser
/// failures propagate (nothing is swallowed).
Future<Tokens> loginVia(
  InHouseOidcClient c,
  FakeBrowser b, {
  String user = 'alice',
  String password = 'alice-pass',
}) async {
  Future<String>? delivery;
  Object? browserError;
  final t = await c
      .signIn(
        present: (u) {
          delivery = b.login(u, user: user, password: password).catchError((
            Object e,
          ) {
            browserError = e;
            c.cancelSignIn();
            return '';
          });
        },
      )
      .catchError((Object e) {
        if (browserError != null) {
          throw StateError('browser failed: $browserError');
        }
        throw e;
      });
  await delivery;
  return t;
}

Dio testDio(Interceptor i) =>
    Dio(BaseOptions(validateStatus: (_) => true))..interceptors.add(i);

Future<bool> portClosed(int port) async {
  try {
    final s = await Socket.connect('127.0.0.1', port);
    s.destroy();
    return false;
  } on SocketException {
    return true;
  }
}

int redirectPort(Uri authUrl) =>
    Uri.parse(authUrl.queryParameters['redirect_uri']!).port;

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
    final t = await loginVia(c, b);
    final at = jwtClaims(t.accessToken);
    final id = jwtClaims(t.idToken!);
    print('B1 callback to ${b.callbackUris.single.replace(query: '')}');
    print(
      'B1 access token iss=${at['iss']} aud=${at['aud']} sub=${at['sub']}; '
      'id token email=${id['email']} email_verified=${id['email_verified']} nonce checked',
    );
    expect(at['aud'], contains(kClientId));
    expect(id['email_verified'], true);
    expect(t.refreshToken, isNotNull);
  });

  test('B2 refresh twice, rotation, single-flight', () async {
    final counter = CountingInterceptor();
    final store = MemoryTokenStore();
    final c = InHouseOidcClient(cfg, store, dio: testDio(counter));
    final t0 = await loginVia(c, FakeBrowser());
    final t1 = await c.refresh();
    final t2 = await c.refresh();
    expect(t1.accessToken, isNot(t0.accessToken));
    expect(t1.refreshToken, isNot(t0.refreshToken));
    expect(t2.refreshToken, isNot(t1.refreshToken));
    expect(store.value!.refreshToken, t2.refreshToken);
    final before = counter.tokenCalls;
    final tokens = await Future.wait(
      List.generate(
        8,
        (_) => c.accessToken(minValidity: const Duration(seconds: 120)),
      ),
    );
    print(
      'B2 8 concurrent accessToken(120s): distinct=${tokens.toSet().length} '
      'token calls=${counter.tokenCalls - before}',
    );
    expect(counter.tokenCalls - before, 1);
    expect(tokens.toSet().length, 1);
  });

  test(
    'B3 revoked refresh token -> SignedOutException, store cleared',
    () async {
      // carol is used only here (bob only in experiment A2b), so revoking his offline
      // token cannot disturb concurrent tests that sign in as alice.
      final admin = KeycloakAdmin();
      final store = MemoryTokenStore();
      final c = InHouseOidcClient(cfg, store);
      await loginVia(c, FakeBrowser(), user: 'carol', password: 'carol-pass');
      await admin.revokeOfflineTokens(await admin.userId('carol'));
      await expectLater(
        c.refresh(),
        throwsA(
          isA<SignedOutException>().having(
            (e) => e.code,
            'code',
            'invalid_grant',
          ),
        ),
      );
      expect(store.value, isNull);
      admin.close();
    },
  );

  test('B4 network error is transient and keeps the session', () async {
    final store = MemoryTokenStore();
    await loginVia(InHouseOidcClient(cfg, store), FakeBrowser());
    final failing = testDio(
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
    await expectLater(c.refresh(), throwsA(isA<TransientAuthException>()));
    expect(store.value, isNotNull);
  });

  test(
    'B4b HTTP error carried by a DioException is still classified',
    () async {
      final store = MemoryTokenStore();
      await loginVia(InHouseOidcClient(cfg, store), FakeBrowser());
      final c = InHouseOidcClient(
        cfg,
        store,
        dio: testDio(
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.uri.path.endsWith('/token')) {
                return h.reject(
                  DioException.badResponse(
                    statusCode: 400,
                    requestOptions: o,
                    response: Response(
                      requestOptions: o,
                      statusCode: 400,
                      data: {'error': 'invalid_grant'},
                    ),
                  ),
                );
              }
              h.next(o);
            },
          ),
        ),
      );
      await expectLater(c.refresh(), throwsA(isA<SignedOutException>()));
      expect(store.value, isNull, reason: 'dead session cleared');
    },
  );

  test(
    'B5 logout: local delete first, revoke, end_session URL, RT dead',
    () async {
      final b = FakeBrowser();
      final store = MemoryTokenStore();
      final c = InHouseOidcClient(cfg, store);
      final t = await loginVia(c, b);
      final rt = t.refreshToken!;
      final end = await c.signOut();
      expect(end, isNotNull);
      print('B5 end_session params=${end!.queryParameters.keys.toList()}');
      expect(store.value, isNull);
      expect(
        end.queryParameters.keys,
        containsAll(['id_token_hint', 'client_id']),
      );
      expect(c.unrevokedRefreshTokens, isEmpty);
      final page = await b.visit(end);
      expect(page.toLowerCase(), contains('logout'));
      final c2 = InHouseOidcClient(
        cfg,
        MemoryTokenStore()
          ..value = Tokens(
            accessToken: 'x',
            expiresAt: DateTime(2000),
            refreshToken: rt,
          ),
      );
      await expectLater(c2.refresh(), throwsA(isA<SignedOutException>()));
      await expectLater(c.accessToken(), throwsA(isA<SignedOutException>()));
    },
  );

  test('B5b unsuccessful revocation is observable and retryable', () async {
    final store = MemoryTokenStore();
    var fail = true;
    final c = InHouseOidcClient(
      cfg,
      store,
      dio: testDio(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (fail && o.uri.path.endsWith('/revoke')) {
              return h.resolve(Response(requestOptions: o, statusCode: 503));
            }
            h.next(o);
          },
        ),
      ),
    );
    await loginVia(c, FakeBrowser());
    await c.signOut();
    expect(store.value, isNull, reason: 'local sign-out happens first');
    expect(c.unrevokedRefreshTokens, hasLength(1));
    expect(c.lastRevocationFailure, contains('503'));
    fail = false;
    expect(await c.retryRevocations(), 0);
  });

  test('B6a port-agnostic redirect', () async {
    final ports = <int>{};
    for (var i = 0; i < 3; i++) {
      final b = FakeBrowser();
      await loginVia(InHouseOidcClient(cfg, MemoryTokenStore()), b);
      ports.add(b.callbackUris.single.port);
    }
    print('B6 loopback ports used: $ports');
    expect(ports.length, greaterThan(1));
  });

  test('B6b manual delivery: URL surfaced, user completes elsewhere', () async {
    final rec = Recorder();
    final c = InHouseOidcClient(cfg, MemoryTokenStore());
    final f = c.signIn(present: rec.call);
    while (rec.urls.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Separate user step: open the recorded URL in "another browser".
    await FakeBrowser().login(rec.urls.single);
    final t = await f;
    expect(rec.urls, hasLength(1));
    expect(t.accessToken, isNotEmpty);
  });

  test('B6c cancel and timeout, also when present never returns', () async {
    final rec = Recorder();
    final c = InHouseOidcClient(cfg, MemoryTokenStore());
    final f = c.signIn(
      present: (u) {
        rec.urls.add(u);
        Timer(const Duration(milliseconds: 200), c.cancelSignIn);
        return Completer<void>().future; // presenter that stays pending
      },
    );
    await expectLater(f, throwsA(isA<SignInException>()));
    expect(await portClosed(redirectPort(rec.urls.single)), isTrue);

    final rec2 = Recorder();
    final c3 = InHouseOidcClient(
      const OidcConfig(
        issuer: kIssuer,
        clientId: kClientId,
        signInTimeout: Duration(seconds: 2),
      ),
      MemoryTokenStore(),
    );
    final sw = Stopwatch()..start();
    await expectLater(
      c3.signIn(
        present: (u) {
          rec2.urls.add(u);
          return Completer<void>().future;
        },
      ),
      throwsA(
        isA<SignInException>().having(
          (e) => e.message,
          'm',
          contains('timed out'),
        ),
      ),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 6)));
    expect(await portClosed(redirectPort(rec2.urls.single)), isTrue);
  });

  test('B7 two environments, independent sessions', () async {
    final s1 = MemoryTokenStore(), s2 = MemoryTokenStore();
    final c1 = InHouseOidcClient(cfg, s1), c2 = InHouseOidcClient(cfg, s2);
    await loginVia(c1, FakeBrowser());
    await loginVia(c2, FakeBrowser());
    expect(s1.value!.refreshToken, isNot(s2.value!.refreshToken));
    final before = s2.value!.refreshToken;
    await c1.refresh();
    await c1.signOut();
    expect(s1.value, isNull);
    expect(s2.value!.refreshToken, before, reason: 'other session untouched');
  });

  test(
    'B8 hardening: overlap, sign-out invalidation, https, id_token',
    () async {
      // Overlapping sign-ins are rejected, the first still completes.
      final rec = Recorder();
      final c = InHouseOidcClient(cfg, MemoryTokenStore());
      final first = c.signIn(present: rec.call);
      await expectLater(
        c.signIn(present: rec.call),
        throwsA(isA<SignInException>()),
      );
      while (rec.urls.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await FakeBrowser().login(rec.urls.single);
      await first;

      // signOut while the token exchange is in flight: result discarded.
      final store = MemoryTokenStore();
      late InHouseOidcClient c2;
      c2 = InHouseOidcClient(
        cfg,
        store,
        dio: testDio(
          InterceptorsWrapper(
            onResponse: (r, h) async {
              if (r.requestOptions.uri.path.endsWith('/token')) {
                await c2.signOut();
              }
              h.next(r);
            },
          ),
        ),
      );
      await expectLater(
        loginVia(c2, FakeBrowser()),
        throwsA(
          isA<SignInException>().having(
            (e) => e.message,
            'message',
            contains('invalidated by sign-out'),
          ),
        ),
      );
      expect(store.value, isNull, reason: 'late result must not be stored');

      // Non-https, non-loopback issuer is refused before any request.
      final c3 = InHouseOidcClient(
        const OidcConfig(
          issuer: 'http://idp.example.test/realms/x',
          clientId: 'c',
        ),
        MemoryTokenStore(),
      );
      await expectLater(
        c3.signIn(present: (_) {}),
        throwsA(isA<SignInException>()),
      );

      // Initial sign-in without id_token is rejected.
      final c4 = InHouseOidcClient(
        cfg,
        MemoryTokenStore(),
        dio: testDio(
          InterceptorsWrapper(
            onResponse: (r, h) {
              if (r.requestOptions.uri.path.endsWith('/token') &&
                  r.data is Map) {
                (r.data as Map).remove('id_token');
              }
              h.next(r);
            },
          ),
        ),
      );
      await expectLater(
        loginVia(c4, FakeBrowser()),
        throwsA(
          isA<SignInException>().having(
            (e) => e.message,
            'm',
            contains('id_token'),
          ),
        ),
      );
    },
  );

  test('B9 sign-out during discovery: no listener, no waiting', () async {
    late InHouseOidcClient c;
    c = InHouseOidcClient(
      cfg,
      MemoryTokenStore(),
      dio: testDio(
        InterceptorsWrapper(
          onResponse: (r, h) async {
            if (r.requestOptions.uri.path.endsWith('openid-configuration')) {
              await c.signOut();
            }
            h.next(r);
          },
        ),
      ),
    );
    var presented = false;
    final sw = Stopwatch()..start();
    await expectLater(
      c.signIn(
        present: (_) {
          presented = true;
        },
      ),
      throwsA(
        isA<SignInException>().having(
          (e) => e.message,
          'message',
          contains('invalidated by sign-out'),
        ),
      ),
    );
    expect(presented, isFalse, reason: 'URL must not be presented');
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    // The client is usable again (no stuck "sign-in active" flag).
    final c2 = InHouseOidcClient(cfg, MemoryTokenStore());
    await loginVia(c2, FakeBrowser());
  });

  test('B10 discovery redirected to plain HTTP is rejected', () async {
    final c = InHouseOidcClient(
      cfg,
      MemoryTokenStore(),
      dio: testDio(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.uri.path.endsWith('openid-configuration')) {
              return h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {'issuer': kIssuer},
                  redirects: [
                    RedirectRecord(
                      302,
                      'GET',
                      Uri.parse('http://idp.example.test/.well-known/x'),
                    ),
                  ],
                ),
              );
            }
            h.next(o);
          },
        ),
      ),
    );
    await expectLater(
      c.signIn(present: (_) {}),
      throwsA(
        isA<SignInException>().having(
          (e) => e.message,
          'message',
          contains('must be https'),
        ),
      ),
    );
  });

  test('B11 unauthorized_client on refresh keeps the session', () async {
    final store = MemoryTokenStore();
    await loginVia(InHouseOidcClient(cfg, store), FakeBrowser());
    final before = store.value!.refreshToken;
    final c = InHouseOidcClient(
      cfg,
      store,
      dio: testDio(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.uri.path.endsWith('/token')) {
              return h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 400,
                  data: {'error': 'unauthorized_client'},
                ),
              );
            }
            h.next(o);
          },
        ),
      ),
    );
    await expectLater(c.refresh(), throwsA(isA<SignInException>()));
    expect(store.value, isNotNull);
    expect(store.value!.refreshToken, before);
  });
}
