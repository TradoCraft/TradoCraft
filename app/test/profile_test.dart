import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/profile.dart';
import 'package:tradocraft_app/app/profile_badge.dart';
import 'package:tradocraft_app/app/session.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

void main() {
  group('profile name', () {
    test('comes from --profile=, --profile <name> or TRAYD_PROFILE', () {
      expect(parseProfile(['--profile=admin'], {}), 'admin');
      expect(parseProfile(['x', '--profile', 'sales'], {}), 'sales');
      expect(parseProfile([], {'TRAYD_PROFILE': 'env'}), 'env');
      expect(parseProfile(['--profile=arg'], {'TRAYD_PROFILE': 'env'}), 'arg');
      expect(parseProfile([], {}), isNull);
      expect(parseProfile(['--profile='], {}), isNull);
    });

    test('is made safe for use as a file name', () {
      expect(sanitizeProfile('../../etc/passwd'), 'etc_passwd');
      expect(sanitizeProfile('a b/c'), 'a_b_c');
      expect(sanitizeProfile('  '), isNull);
      expect(sanitizeProfile('x' * 80)!.length, 32);
    });
  });

  group('JsonFileKvStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('profiles'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('two profiles do not clobber each other', () async {
      final admin = JsonFileKvStore.forProfile('admin', dir: dir);
      final sales = JsonFileKvStore.forProfile('sales', dir: dir);
      await SessionStore.save(
        const Session(serverUrl: 'http://s', devUser: 'admin@example.com'),
        admin,
      );
      await SessionStore.save(
        const Session(serverUrl: 'http://s', devUser: 'sales@example.com'),
        sales,
      );
      await admin.set('locale', 'de');
      await sales.set('locale', 'fr');

      // Fresh stores read the files as a new process would.
      final a = JsonFileKvStore.forProfile('admin', dir: dir);
      final s = JsonFileKvStore.forProfile('sales', dir: dir);
      expect((await SessionStore.load(a)).devUser, 'admin@example.com');
      expect((await SessionStore.load(s)).devUser, 'sales@example.com');
      expect(await a.get('locale'), 'de');
      expect(await s.get('locale'), 'fr');
      expect(
        File('${dir.path}/profiles/admin.json').existsSync() &&
            File('${dir.path}/profiles/sales.json').existsSync(),
        isTrue,
      );
    });

    test('remove deletes a key and a broken file reads as empty', () async {
      final store = JsonFileKvStore.forProfile('p', dir: dir);
      await store.set('k', 'v');
      await store.remove('k');
      expect(await JsonFileKvStore.forProfile('p', dir: dir).get('k'), isNull);

      File('${dir.path}/profiles/p.json').writeAsStringSync('{not json');
      expect(await JsonFileKvStore.forProfile('p', dir: dir).get('k'), isNull);
    });

    test('concurrent writes all end up in the file', () async {
      final store = JsonFileKvStore.forProfile('p', dir: dir);
      await Future.wait([for (var i = 0; i < 20; i++) store.set('k$i', '$i')]);
      final again = JsonFileKvStore.forProfile('p', dir: dir);
      for (var i = 0; i < 20; i++) {
        expect(await again.get('k$i'), '$i');
      }
    });
  });

  test('the session store keeps the old keys without a profile', () async {
    final store = MemoryKvStore();
    await SessionStore.save(
      const Session(serverUrl: 'http://s', devUser: 'a@b.c', companyId: 'co'),
      store,
    );
    expect(store.data['server_url'], 'http://s');
    expect(store.data['dev_user'], 'a@b.c');
    expect(store.data['company_id'], 'co');
    expect((await SessionStore.load(store)).isSignedIn, isTrue);
  });

  test('sign-in and language go to the profile store', () async {
    final store = MemoryKvStore();
    final c = ProviderContainer(
      overrides: [kvStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    await c
        .read(sessionProvider.notifier)
        .signIn(const Session(serverUrl: 'http://s', devUser: 'x@y.z'));
    await c.read(localeProvider.notifier).set(const Locale('nl'));
    expect(store.data['dev_user'], 'x@y.z');
    expect(store.data['locale'], 'nl');
  });

  test('a slow read of the stored language does not undo a choice', () async {
    final store = _SlowStore(MemoryKvStore()..data['locale'] = 'fr');
    final c = ProviderContainer(
      overrides: [kvStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    c.read(localeProvider);
    await c.read(localeProvider.notifier).set(const Locale('nl'));
    store.release();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(localeProvider), const Locale('nl'));
  });

  test('the stored language is applied when nothing was chosen', () async {
    final store = MemoryKvStore()..data['locale'] = 'es';
    final c = ProviderContainer(
      overrides: [kvStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    c.read(localeProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(localeProvider), const Locale('es'));
  });

  group('shell badge', () {
    Future<void> pumpShell(WidgetTester tester, {String? profile}) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['quotations.read']),
      });
      final router = GoRouter(
        initialLocation: '/quotations',
        routes: [
          ShellRoute(
            builder: (c, s, child) =>
                AppShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(
                path: '/quotations',
                builder: (_, _) => const Text('QUOTES'),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(fakeDio(http)),
            profileProvider.overrideWithValue(profile),
            kvStoreProvider.overrideWithValue(MemoryKvStore()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the profile name and the roles', (tester) async {
      await pumpShell(tester, profile: 'sales');
      final badge = find.byKey(const ValueKey('profile-badge'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('sales')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: badge, matching: find.text('support')),
        findsOneWidget,
      );
    });

    testWidgets('is absent without a profile', (tester) async {
      await pumpShell(tester);
      expect(find.byKey(const ValueKey('profile-badge')), findsNothing);
    });

    test('colours differ per profile and are stable', () {
      expect(
        ProfileBadge.colorFor('admin'),
        isNot(ProfileBadge.colorFor('sales')),
      );
      expect(ProfileBadge.colorFor('admin'), ProfileBadge.colorFor('admin'));
    });
  });
}

/// A store whose reads wait until [release], to make a read finish after later writes.
class _SlowStore implements KvStore {
  _SlowStore(this._inner);
  final KvStore _inner;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<String?> get(String key) async {
    final v = await _inner.get(key);
    await _gate.future;
    return v;
  }

  @override
  Future<void> set(String key, String value) => _inner.set(key, value);

  @override
  Future<void> remove(String key) => _inner.remove(key);
}
