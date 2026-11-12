// Experiment A: the `oidc` package family (oidc_core manager + oidc_desktop
// loopback listener, i.e. the Linux path) against a local Keycloak, with the
// test acting as the browser. Run: flutter test test/experiment_a_oidc_test.dart
// (needs `docker compose up -d`, see README). The tests print their evidence.
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:oidc/oidc.dart';
import 'package:oidc_linux/oidc_linux.dart';
import 'package:oidc_spike/fake_browser.dart';
import 'package:oidc_spike/keycloak_admin.dart';
import 'package:test/test.dart';

const _scopes = ['openid', 'profile', 'email', 'offline_access'];

/// Builds a manager whose "browser launch" is handed to [onUrl].
OidcUserManager newManager({
  required FutureOr<bool> Function(Uri) onUrl,
  OidcStore? store,
  String redirect = 'http://127.0.0.1:0/callback',
  http.Client? client,
  String? id,
  int timeoutSeconds = 20,
  List<String> scopes = _scopes,
}) {
  return OidcUserManager.lazy(
    discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
      Uri.parse(kIssuer),
    ),
    clientCredentials: const OidcClientAuthentication.none(clientId: kClientId),
    store: store ?? OidcMemoryStore(),
    id: id,
    httpClient: client,
    settings: OidcUserManagerSettings(
      redirectUri: Uri.parse(redirect),
      postLogoutRedirectUri: Uri.parse('http://127.0.0.1:0/logout-done'),
      scope: scopes,
      options: OidcPlatformSpecificOptions(
        linux: OidcPlatformSpecificOptions_Native(
          flowTimeoutSeconds: timeoutSeconds,
          launchUrl: (url) async => onUrl(url),
        ),
      ),
    ),
  );
}

/// Launch hook that drives [b]: login for auth URLs, visit for logout.
Future<bool> Function(Uri) browserDriver(FakeBrowser b, {List<Uri>? seen}) =>
    (u) async {
      seen?.add(u);
      unawaited(
        (u.path.endsWith('/logout') ? b.visit(u) : b.login(u)).catchError(
          (Object e) => 'browser error: $e',
        ),
      );
      return true;
    };

Stream<OidcTokenRefreshFailedEvent> failedEvents(OidcUserManager m) => m
    .events()
    .where((e) => e is OidcTokenRefreshFailedEvent)
    .cast<OidcTokenRefreshFailedEvent>();

void main() {
  setUpAll(() {
    OidcPlatform.instance = OidcLinux();
    if (const bool.fromEnvironment('OIDC_LOG')) {
      Logger.root.level = Level.FINE;
      Logger.root.onRecord.listen(
        (r) => print('[${r.loggerName}] ${r.message} ${r.error ?? ''}'),
      );
    }
  });

  test('A1 code+PKCE login via loopback, claims', () async {
    final browser = FakeBrowser();
    final seen = <Uri>[];
    final m = newManager(onUrl: browserDriver(browser, seen: seen));
    await m.init();
    final user = await m.loginAuthorizationCodeFlow();
    expect(user, isNotNull);
    print('auth URL params: ${seen.first.queryParameters}');
    print(
      'callback delivered to: ${browser.callbackUris.single.replace(query: '')}',
    );
    final at = jwtClaims(user!.token.accessToken!);
    print(
      'access token: iss=${at['iss']} aud=${at['aud']} sub=${at['sub']} '
      'lifetime=${at['exp'] - at['iat']}s azp=${at['azp']} typ=${at['typ']}',
    );
    print(
      'id token: iss=${user.claims['iss']} aud=${user.claims['aud']} '
      'sub=${user.claims['sub']} email=${user.claims['email']} '
      'email_verified=${user.claims['email_verified']} nonce=${user.claims['nonce'] != null}',
    );
    print(
      'refresh token typ=${jwtClaims(user.token.refreshToken!)['typ']} '
      'scope=${user.token.scope}',
    );
    expect(at['iss'], kIssuer);
    expect(at['aud'], contains(kClientId));
    expect(user.claims['email_verified'], true);
    await m.dispose();
  });

  test('A2 refresh twice: what changes; reuse of a rotated token', () async {
    final browser = FakeBrowser();
    final http1 = LoggingClient();
    final m = newManager(onUrl: browserDriver(browser), client: http1);
    await m.init();
    final u0 = await m.loginAuthorizationCodeFlow();
    final rt0 = u0!.token.refreshToken!;
    final u1 = (await m.refreshToken())!;
    final u2 = (await m.refreshToken())!;
    print(
      'refresh#1: access token changed=${u1.token.accessToken != u0.token.accessToken} '
      'refresh token changed=${u1.token.refreshToken != rt0} '
      'id token returned=${u1.token.idToken != null} sub same=${u1.claims['sub'] == u0.claims['sub']}',
    );
    print(
      'refresh#2: refresh token changed vs #1=${u2.token.refreshToken != u1.token.refreshToken}',
    );
    print(
      'manager currentUser holds newest RT: ${m.currentUser?.token.refreshToken == u2.token.refreshToken}',
    );
    Object? err;
    OidcUser? reused;
    try {
      reused = await m.refreshToken(overrideRefreshToken: rt0);
    } catch (e) {
      err = e;
    }
    print(
      'reuse of an already-rotated RT -> returned user=${reused != null} error=$err',
    );
    print('http calls: ${http1.log}');
    await m.dispose();
  });

  test('A2b administrator revokes the offline token -> invalid_grant', () async {
    final browser = FakeBrowser();
    final admin = KeycloakAdmin();
    final m = newManager(onUrl: browserDriver(browser));
    await m.init();
    final failures = <OidcTokenRefreshFailedEvent>[];
    final sub = failedEvents(m).listen(failures.add);
    final userStream = <String>[];
    final us = m.userChanges().listen(
      (u) => userStream.add(u == null ? 'null' : 'user'),
    );
    await m.loginAuthorizationCodeFlow();
    await admin.revokeOfflineTokens(await admin.userId('alice'));
    Object? err;
    try {
      await m.refreshToken();
    } catch (e) {
      err = e;
    }
    print('manual refresh after revoke -> ${err.runtimeType}');
    if (err is OidcException) {
      print(
        '  errorResponse=${err.errorResponse?.error} desc=${err.errorResponse?.errorDescription}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final f in failures) {
      print(
        'FAILED EVENT: kind=${f.kind} code=${f.oauthErrorCode} http=${f.httpStatusCode} '
        'source=${f.source} willRetry=${f.willRetry}',
      );
    }
    print('userChanges stream: $userStream');
    print(
      'currentUser after terminal failure: '
      '${m.currentUser == null ? 'null (signed out)' : 'still set (stale)'}',
    );
    Object? err2;
    String? at;
    try {
      at = await m.getAccessToken(minValidity: const Duration(seconds: 120));
    } catch (e) {
      err2 = e;
    }
    print(
      'getAccessToken on dead session -> token=${at == null ? null : 'returned'} '
      'error=${err2.runtimeType}: $err2',
    );
    await us.cancel();
    await sub.cancel();
    await m.dispose();
    admin.close();
  });

  test('A2c online (non-offline) refresh token: reuse of a rotated token', () async {
    final browser = FakeBrowser();
    final m = newManager(
      onUrl: browserDriver(browser),
      scopes: const ['openid', 'profile', 'email'],
    );
    await m.init();
    final failures = <OidcTokenRefreshFailedEvent>[];
    final sub = failedEvents(m).listen(failures.add);
    final u0 = await m.loginAuthorizationCodeFlow();
    final rt0 = u0!.token.refreshToken!;
    print('online RT typ=${jwtClaims(rt0)['typ']}');
    final u1 = (await m.refreshToken())!;
    Object? err;
    try {
      await m.refreshToken(overrideRefreshToken: rt0);
    } catch (e) {
      err = e;
    }
    print(
      'reuse of rotated online RT -> '
      '${err is OidcException ? 'OidcException ${err.errorResponse?.error}: ${err.errorResponse?.errorDescription}' : err}',
    );
    Object? err2;
    try {
      await m.refreshToken();
    } catch (e) {
      err2 = e;
    }
    print(
      'then the legitimate newest RT (family revoked by reuse detection?) -> '
      '${err2 is OidcException ? err2.errorResponse?.error : err2 ?? 'still works'} '
      '(rotated once ${u1.token.refreshToken != rt0})',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    print(
      'failed events: ${failures.map((f) => '${f.kind.name}/${f.oauthErrorCode}').toList()}',
    );
    await sub.cancel();
    await m.dispose();
  });

  test('A3 concurrent getAccessToken shares one refresh', () async {
    final browser = FakeBrowser();
    final http1 = LoggingClient();
    final m = newManager(onUrl: browserDriver(browser), client: http1);
    await m.init();
    await m.loginAuthorizationCodeFlow();
    final before = http1.log.where((l) => l.contains('/token')).length;
    // The access token lives 60 s; asking for 120 s validity forces a refresh.
    final results = await Future.wait(
      List.generate(
        8,
        (_) => m.getAccessToken(minValidity: const Duration(seconds: 120)),
      ),
    );
    final tokenCalls =
        http1.log.where((l) => l.contains('/token')).length - before;
    print(
      '8 concurrent getAccessToken(minValidity 120s): '
      'distinct tokens=${results.toSet().length}, token endpoint calls=$tokenCalls',
    );
    await m.dispose();
  });

  test('A4 RP-initiated logout (end_session + id_token_hint)', () async {
    final browser = FakeBrowser();
    final seen = <Uri>[];
    final m = newManager(onUrl: browserDriver(browser, seen: seen));
    await m.init();
    await m.loginAuthorizationCodeFlow();
    final rt = m.currentUser!.token.refreshToken!;
    await m.logout().timeout(const Duration(seconds: 30));
    final logoutUrl = seen.firstWhere((u) => u.path.endsWith('/logout'));
    print('logout URL params: ${logoutUrl.queryParameters.keys.toList()}');
    print('after logout: currentUser=${m.currentUser}');
    Object? err;
    try {
      await m.refreshToken(overrideRefreshToken: rt);
    } catch (e) {
      err = e;
    }
    print(
      'refresh with pre-logout RT -> ${err == null ? 'ACCEPTED' : err.runtimeType}: $err',
    );
    await m.dispose();
  });

  test('A5 port-agnostic redirect: the OP accepted random ports', () async {
    final ports = <int>{};
    for (var i = 0; i < 3; i++) {
      final b = FakeBrowser();
      final m = newManager(onUrl: browserDriver(b));
      await m.init();
      await m.loginAuthorizationCodeFlow();
      ports.add(b.callbackUris.single.port);
      await m.dispose();
    }
    print(
      'three logins used loopback ports $ports (redirect registered as http://127.0.0.1/*)',
    );
    expect(ports.length, greaterThan(1));
  });

  test('A5b a redirect host the client does not allow is rejected', () async {
    final b = FakeBrowser();
    final m = newManager(
      onUrl: browserDriver(b),
      redirect: 'http://localhost:0/callback',
      timeoutSeconds: 5,
    );
    await m.init();
    Object? err;
    try {
      await m.loginAuthorizationCodeFlow();
    } catch (e) {
      err = e;
    }
    print(
      'redirect_uri http://localhost:<port>/callback -> ${err.runtimeType}: $err',
    );
    await m.dispose();
  });

  test('A6 browser cannot be opened: launch hook returns false / shows URL', () async {
    // (a) hook returns false: the package only logs a warning and keeps waiting.
    var shown = false;
    final m = newManager(
      onUrl: (u) {
        shown = true;
        return false;
      },
      timeoutSeconds: 4,
    );
    await m.init();
    final sw = Stopwatch()..start();
    Object? err;
    try {
      await m.loginAuthorizationCodeFlow();
    } catch (e) {
      err = e;
    }
    print(
      'launchUrl=false: hook called=$shown, flow ended after ${sw.elapsed.inSeconds}s with $err',
    );
    await m.dispose();

    // (b) the app shows the URL, user opens it elsewhere: the hook returns
    // true after publishing the URL to the UI.
    final browser = FakeBrowser();
    final shownUrls = <Uri>[];
    final m2 = newManager(
      onUrl: (u) {
        shownUrls.add(u); // UI would render this as copyable text
        unawaited(browser.login(u)); // "user" opens it elsewhere
        return true;
      },
    );
    await m2.init();
    final user = await m2.loginAuthorizationCodeFlow();
    print(
      'URL shown to user then completed elsewhere: user=${user != null}, '
      'url host=${shownUrls.single.host}',
    );
    await m2.dispose();
  });

  test('A7 several managers (two environments) with one store', () async {
    final store = OidcMemoryStore();
    final b1 = FakeBrowser(), b2 = FakeBrowser();
    final m1 = newManager(
      onUrl: browserDriver(b1),
      store: store,
      id: 'env-live',
    );
    final m2 = newManager(
      onUrl: browserDriver(b2),
      store: store,
      id: 'env-test',
    );
    await m1.init();
    await m2.init();
    final u1 = await m1.loginAuthorizationCodeFlow();
    final u2 = await m2.loginAuthorizationCodeFlow();
    print(
      'two managers, one store, distinct ids: '
      'rt differ=${u1!.token.refreshToken != u2!.token.refreshToken}, '
      'both signed in=${m1.currentUser != null && m2.currentUser != null}',
    );
    final m1b = newManager(onUrl: (_) => false, store: store, id: 'env-live');
    await m1b.init();
    print(
      'restored session for env-live after "restart": '
      '${m1b.currentUser?.claims['sub'] == u1.claims['sub']}',
    );
    await m1.dispose();
    await m2.dispose();
    await m1b.dispose();
  });
}
