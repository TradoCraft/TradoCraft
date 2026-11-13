// Runs inside a real Flutter Linux app (needs a display, a session D-Bus and
// an unlocked Secret Service). Under Xvfb + gnome-keyring, see README:
//   flutter test integration_test/store_probe_test.dart -d linux
// Proves oidc_default_store + flutter_secure_storage (libsecret) + the real
// oidc_linux/url_launcher plugins work, and that a session survives a restart.
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';
import 'package:oidc_spike/fake_browser.dart';
import 'package:test/test.dart';

OidcUserManager manager(
  OidcStore store,
  FakeBrowser b, {
  String id = 'env-live',
}) => OidcUserManager.lazy(
  discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
    Uri.parse(kIssuer),
  ),
  clientCredentials: const OidcClientAuthentication.none(clientId: kClientId),
  store: store,
  id: id,
  settings: OidcUserManagerSettings(
    redirectUri: Uri.parse('http://127.0.0.1:0/callback'),
    scope: const ['openid', 'profile', 'email', 'offline_access'],
    options: OidcPlatformSpecificOptions(
      linux: OidcPlatformSpecificOptions_Native(
        flowTimeoutSeconds: 20,
        launchUrl: (u) async {
          unawaited(b.login(u));
          return true;
        },
      ),
    ),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('real plugins: login, secure store, restore after restart', () async {
    const probe = FlutterSecureStorage();
    await probe.write(key: 'probe', value: 'ok');
    print(
      'flutter_secure_storage (libsecret) round trip: ${await probe.read(key: 'probe')}',
    );
    await probe.delete(key: 'probe');

    final store = OidcDefaultStore();
    final m = manager(store, FakeBrowser());
    await m.init();
    final user = await m.loginAuthorizationCodeFlow();
    expect(user, isNotNull);
    print('login with OidcDefaultStore: ${user!.claims['email']}');
    await m.dispose();

    // "Restart": new store + new manager with the same id.
    final store2 = OidcDefaultStore();
    final m2 = manager(store2, FakeBrowser());
    await m2.init();
    print(
      'restored from keyring after restart: ${m2.currentUser?.claims['email']} '
      'refresh token present=${m2.currentUser?.token.refreshToken != null}',
    );
    expect(m2.currentUser, isNotNull);
    expect(m2.currentUser!.claims['sub'], user.claims['sub']);
    expect(m2.currentUser!.token.refreshToken, isNotNull);
    // A different environment id must not see this session.
    final m3 = manager(OidcDefaultStore(), FakeBrowser(), id: 'env-test');
    await m3.init();
    expect(m3.currentUser, isNull);
    await m2.forgetUser();
    await m2.dispose();
    await m3.dispose();
  });
}
