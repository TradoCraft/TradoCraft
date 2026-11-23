import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/field/offline/kv_store.dart';
import '../features/products/product_thumb.dart' show clearProductThumbCache;
import 'shortcuts/actions.dart' show ShortcutBindings;

/// Connection and identity of the signed-in user.
///
/// Two modes:
/// * development: the API runs with AUTH_MODE=dev and trusts the `X-Dev-User` e-mail;
/// * token: an OpenID Connect access token is sent as `Authorization: Bearer`.
///   (An interactive OIDC sign-in flow replaces the pasted token in a later release.)
class Session {
  const Session({
    required this.serverUrl,
    this.devUser,
    this.accessToken,
    this.companyId,
  });

  final String serverUrl;
  final String? devUser;
  final String? accessToken;
  final String? companyId;

  bool get isSignedIn =>
      (devUser?.isNotEmpty ?? false) || (accessToken?.isNotEmpty ?? false);

  Map<String, String> get headers => {
    if (devUser?.isNotEmpty ?? false) 'X-Dev-User': devUser!,
    if (accessToken?.isNotEmpty ?? false)
      'Authorization': 'Bearer $accessToken',
    'X-Company-Id': ?companyId,
  };

  static final signedOut = Session(
    serverUrl: kIsWeb && const bool.fromEnvironment('TRADOCRAFT_SAME_ORIGIN')
        ? Uri.base.origin
        : 'http://localhost:8080',
  );
}

class SessionStore {
  static const _server = 'server_url',
      _dev = 'dev_user',
      _token = 'access_token',
      _company = 'company_id';

  /// The e-mail last used to sign in; kept on sign-out so a profile's login page remembers it.
  static const lastDevUserKey = 'last_dev_user';

  /// Reads the session from [store]: the default storage (SharedPreferences) without a profile,
  /// the profile's own file with one.
  static Future<Session> load(KvStore store) async => Session(
    serverUrl: await store.get(_server) ?? Session.signedOut.serverUrl,
    devUser: await store.get(_dev),
    accessToken: await store.get(_token),
    companyId: await store.get(_company),
  );

  static Future<void> save(Session s, KvStore store) async {
    await store.set(_server, s.serverUrl);
    Future<void> put(String k, String? v) =>
        v == null ? store.remove(k) : store.set(k, v);
    await put(_dev, s.devUser);
    await put(_token, s.accessToken);
    await put(_company, s.companyId);
    if (s.devUser?.isNotEmpty ?? false) {
      await store.set(lastDevUserKey, s.devUser!);
    }
  }
}

/// Session read from storage at start-up (overridden in main / tests).
final initialSessionProvider = Provider<Session>((ref) => Session.signedOut);

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() => ref.read(initialSessionProvider);

  Future<void> signIn(Session s) async {
    clearProductThumbCache();
    state = s;
    await SessionStore.save(s, ref.read(kvStoreProvider));
  }

  Future<void> signOut() async {
    clearProductThumbCache();
    ShortcutBindings.setOverrides(const {});
    state = Session(serverUrl: state.serverUrl);
    await SessionStore.save(state, ref.read(kvStoreProvider));
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(
  SessionNotifier.new,
);

/// The app's language; null follows the device language.
class LocaleNotifier extends Notifier<Locale?> {
  static const _key = 'locale';

  /// Set once the user (or the app) has chosen a language, so a slower read of the stored one
  /// cannot overwrite that choice.
  bool _changed = false;

  @override
  Locale? build() {
    _changed = false;
    ref.read(kvStoreProvider).get(_key).then((code) {
      if (!_changed && ref.mounted && code != null && code.isNotEmpty) {
        state = Locale(code);
      }
    }, onError: (Object _) {});
    return null;
  }

  /// Chooses the language (null = follow the device) and stores it.
  Future<void> set(Locale? locale) async {
    _changed = true;
    state = locale;
    final store = ref.read(kvStoreProvider);
    if (locale == null) {
      await store.remove(_key);
    } else {
      await store.set(_key, locale.languageCode);
    }
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
