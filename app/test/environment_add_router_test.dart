import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/environment_ui.dart';
import 'package:tradocraft_app/app/environments.dart';
import 'package:tradocraft_app/app/session.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/login/login_page.dart';
import 'package:tradocraft_app/features/setup/setup_api.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

// Regression: adding an environment switches the session, and the session-based redirect rebuilds
// the page stack. The add dialog used to pop after that and asserted "popped the last page".

const _url1 = 'https://erp.example.com';
const _url2 = 'http://localhost:8091';

const _probeInfo = EnvironmentProbe(
  name: 'Practice',
  kind: EnvironmentKind.tutorial,
  dbName: 'practice',
  version: '0.1.0',
);

/// Builds the app with a real router: signed out goes to /login, signed in to the shell.
Future<({ProviderContainer c, GoRouter router})> _open(
  WidgetTester tester, {
  required bool signedIn,
  bool needsSetup = false,
  Future<SetupStatusInfo> Function(String)? setupStatus,
}) async {
  final env = AppEnvironment(
    id: 'env-1',
    name: 'Acme production',
    kind: EnvironmentKind.live,
    serverUrl: _url1,
    devUser: signedIn ? 'admin@example.com' : null,
    companyId: signedIn ? 'company-1' : null,
  );
  final envs = EnvironmentsState(items: [env], activeId: env.id);
  final c = ProviderContainer(
    overrides: [
      kvStoreProvider.overrideWithValue(MemoryKvStore()),
      initialEnvironmentsProvider.overrideWithValue(envs),
      initialSessionProvider.overrideWithValue(env.session),
      environmentProbeProvider.overrideWithValue((url) async => _probeInfo),
      setupStatusProvider.overrideWithValue(
        setupStatus ??
            (_) async => SetupStatusInfo(
              needsSetup: needsSetup,
              tokenRequired: false,
              authMode: 'dev',
            ),
      ),
    ],
  );
  addTearDown(c.dispose);
  final listenable = ValueNotifier(c.read(sessionProvider).isSignedIn);
  c.listen(sessionProvider, (_, s) => listenable.value = s.isSignedIn);
  addTearDown(listenable.dispose);
  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: listenable,
    redirect: (_, state) {
      final atLogin =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/setup';
      if (!listenable.value) return atLogin ? null : '/login';
      return atLogin ? '/home' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/setup',
        builder: (_, s) => Text('WIZARD ${s.uri.queryParameters['server']}'),
      ),
      ShellRoute(
        builder: (_, _, child) => Scaffold(
          body: Column(
            children: [const EnvironmentBanner(), Expanded(child: child)],
          ),
        ),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => Builder(
              // The direct entry point, as the tutorial chapter map uses it.
              builder: (context) => TextButton(
                key: const ValueKey('open-add'),
                onPressed: () => showAddEnvironmentDialog(context),
                child: const Text('HOME'),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  if (signedIn) {
    final ws = c.read(workspaceProvider.notifier);
    ws.open('/orders/o1');
    ws.open('/quotations/q1');
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (c: c, router: router);
}

Future<void> _openAddDialog(
  WidgetTester tester, {
  required bool fromLogin,
  bool direct = false,
}) async {
  if (direct) {
    await tester.tap(find.byKey(const ValueKey('open-add')));
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(
    fromLogin
        ? find.byKey(const ValueKey('login-environments'))
        : find.byType(EnvironmentBanner),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('env-add')));
  await tester.pumpAndSettle();
}

Future<void> _checkAndAdd(WidgetTester tester, String url) async {
  await tester.enterText(find.byKey(const ValueKey('env-url')), url);
  await tester.tap(find.byKey(const ValueKey('env-check')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('env-add-confirm')));
  await tester.pumpAndSettle();
}

String _location(GoRouter r) =>
    r.routerDelegate.currentConfiguration.uri.toString();

void main() {
  for (final entry in ['switcher', 'login', 'direct']) {
    final fromLogin = entry == 'login';
    final direct = entry == 'direct';
    final where = fromLogin
        ? 'the login page'
        : direct
        ? 'showAddEnvironmentDialog'
        : 'the switcher in the shell';
    testWidgets('adding from $where closes the dialogs without a crash', (
      tester,
    ) async {
      final t = await _open(tester, signedIn: !fromLogin);
      await _openAddDialog(tester, fromLogin: fromLogin, direct: direct);
      await _checkAndAdd(tester, _url2);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('env-add-confirm')), findsNothing);
      expect(find.byKey(const ValueKey('env-add')), findsNothing);
      final state = t.c.read(environmentsProvider);
      expect(state.items, hasLength(2));
      expect(state.active.serverUrl, _url2);
      expect(t.c.read(workspaceProvider).tabs, isEmpty);
      expect(_location(t.router), '/login');
      expect(find.byType(LoginPage), findsOneWidget);
    });
  }
  for (final direct in [false, true]) {
  for (final accept in [true, false]) {
    final what = '${direct ? 'direct entry, ' : ''}${accept
        ? 'accepting opens the wizard'
        : 'declining ends on the login page'}';
    testWidgets('a server that needs setup: $what', (tester) async {
      final t = await _open(tester, signedIn: true, needsSetup: true);
      await _openAddDialog(tester, fromLogin: false, direct: direct);
      await _checkAndAdd(tester, _url2);
      expect(find.text('Set up this server?'), findsOneWidget);
      await tester.tap(
        find.byKey(
          ValueKey(accept ? 'setup-offer-open' : 'setup-offer-later'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('env-add-confirm')), findsNothing);
      expect(t.c.read(environmentsProvider).active.serverUrl, _url2);
      expect(t.c.read(workspaceProvider).tabs, isEmpty);
      if (accept) {
        expect(
          _location(t.router),
          '/setup?server=${Uri.encodeQueryComponent(_url2)}',
        );
        expect(find.text('WIZARD $_url2'), findsOneWidget);
      } else {
        expect(_location(t.router), '/login');
        expect(find.byType(LoginPage), findsOneWidget);
      }
    });
  }
  }

  testWidgets('an address that is already listed keeps the dialog open', (
    tester,
  ) async {
    final t = await _open(tester, signedIn: true);
    await _openAddDialog(tester, fromLogin: false);
    await _checkAndAdd(tester, _url1);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('env-add-confirm')), findsOneWidget);
    expect(find.text('This server is already in the list.'), findsOneWidget);
    expect(t.c.read(environmentsProvider).items, hasLength(1));
    expect(_location(t.router), '/home');
  });

  group('single submission', () {
    Finder addButton() => find.byKey(const ValueKey('env-add-confirm'));
    bool enabled(WidgetTester tester) =>
        tester.widget<FilledButton>(addButton()).onPressed != null;

    testWidgets('a double tap asks for the setup status once and adds once', (
      tester,
    ) async {
      final gate = Completer<SetupStatusInfo>();
      var calls = 0;
      final t = await _open(
        tester,
        signedIn: true,
        setupStatus: (_) {
          calls++;
          return gate.future;
        },
      );
      await _openAddDialog(tester, fromLogin: false);
      await tester.enterText(find.byKey(const ValueKey('env-url')), _url2);
      await tester.tap(find.byKey(const ValueKey('env-check')));
      await tester.pumpAndSettle();
      await tester.tap(addButton());
      await tester.pump();
      expect(enabled(tester), isFalse);
      await tester.tap(addButton(), warnIfMissed: false);
      await tester.pump();
      // Only the dialog asked so far (the login page asks too once the app lands on it).
      expect(calls, 1);
      gate.complete(
        const SetupStatusInfo(
          needsSetup: false,
          tokenRequired: false,
          authMode: 'dev',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(t.c.read(environmentsProvider).items, hasLength(2));
      expect(addButton(), findsNothing);
    });

    testWidgets('Add works again after a duplicate found at the last moment', (
      tester,
    ) async {
      final t = await _open(tester, signedIn: true);
      await _openAddDialog(tester, fromLogin: false);
      await tester.enterText(find.byKey(const ValueKey('env-url')), _url2);
      await tester.tap(find.byKey(const ValueKey('env-check')));
      await tester.pumpAndSettle();
      // The same address is stored by another way while the dialog is open.
      t.c.read(environmentsProvider.notifier).state = t.c
          .read(environmentsProvider)
          .copyWith(
            items: [
              ...t.c.read(environmentsProvider).items,
              const AppEnvironment(
                id: 'env-9',
                name: 'Same',
                kind: EnvironmentKind.test,
                serverUrl: _url2,
              ),
            ],
          );
      await tester.tap(addButton());
      await tester.pumpAndSettle();
      expect(find.text('This server is already in the list.'), findsOneWidget);
      expect(enabled(tester), isTrue);
    });

    testWidgets('the setup offer blocks a second submission and later still adds', (
      tester,
    ) async {
      final t = await _open(tester, signedIn: true, needsSetup: true);
      await _openAddDialog(tester, fromLogin: false);
      await tester.enterText(find.byKey(const ValueKey('env-url')), _url2);
      await tester.tap(find.byKey(const ValueKey('env-check')));
      await tester.pumpAndSettle();
      await tester.tap(addButton());
      await tester.pumpAndSettle();
      // The offer is open: the dialog behind it cannot be submitted again.
      expect(find.byKey(const ValueKey('setup-offer-later')), findsOneWidget);
      expect(enabled(tester), isFalse);
      // The offer's own buttons close only the offer; adding goes on to a closed dialog.
      await tester.tap(find.byKey(const ValueKey('setup-offer-later')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(addButton(), findsNothing);
      expect(t.c.read(environmentsProvider).items, hasLength(2));
    });

    testWidgets('a setup status that arrives after Cancel adds and pops nothing', (
      tester,
    ) async {
      final gate = Completer<SetupStatusInfo>();
      final t = await _open(
        tester,
        signedIn: true,
        setupStatus: (_) => gate.future,
      );
      await _openAddDialog(tester, fromLogin: false);
      await tester.enterText(find.byKey(const ValueKey('env-url')), _url2);
      await tester.tap(find.byKey(const ValueKey('env-check')));
      await tester.pumpAndSettle();
      await tester.tap(addButton());
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(addButton(), findsNothing);
      // The switcher behind the add dialog is still there.
      expect(find.byKey(const ValueKey('env-add')), findsOneWidget);
      gate.complete(
        const SetupStatusInfo(
          needsSetup: true,
          tokenRequired: false,
          authMode: 'dev',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('env-add')), findsOneWidget);
      expect(find.text('Set up this server?'), findsNothing);
      expect(t.c.read(environmentsProvider).items, hasLength(1));
    });
  });
}
