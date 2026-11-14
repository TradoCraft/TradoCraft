import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/environments.dart';
import 'package:tradocraft_app/app/session.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/login/login_page.dart';
import 'package:tradocraft_app/features/setup/setup_api.dart';
import 'package:tradocraft_app/features/setup/setup_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Future<EnvironmentProbe> _probe(String url) async => const EnvironmentProbe(
  name: 'Fresh',
  kind: EnvironmentKind.live,
  dbName: 'fresh',
  version: '1',
);

Map<String, Object?> _status({
  bool needs = true,
  bool token = false,
  String mode = 'dev',
}) => {'needs_setup': needs, 'token_required': token, 'auth_mode': mode};

Map<String, Object?> _created(String mode) => {
  'company': {'id': 'c1', 'name': 'Fresh Co'},
  'admin': {
    'user_id': 'u1',
    'email': 'boss@fresh.example',
    'display_name': 'The Boss',
    'roles': ['admin'],
  },
  'auth_mode': mode,
};

/// Pumps the app with `/login` and `/setup` routes on a [FakeHttp] server.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeHttp http, {
  String initial = '/setup',
  Session? session,
}) async {
  final c = ProviderContainer(
    overrides: [
      setupDioProvider.overrideWithValue((_) => fakeDio(http)),
      kvStoreProvider.overrideWithValue(MemoryKvStore()),
      environmentProbeProvider.overrideWithValue(_probe),
      if (session != null) initialSessionProvider.overrideWithValue(session),
    ],
  );
  addTearDown(c.dispose);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/setup',
        builder: (_, state) =>
            SetupPage(server: state.uri.queryParameters['server']),
      ),
      GoRoute(path: '/quotations', builder: (_, _) => const Text('HOME')),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(ValueKey('setup-$key')), text);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Fills the first three steps and stops on the one after them.
Future<void> _fillAll(WidgetTester tester) async {
  await _type(tester, 'name', 'Fresh Co');
  await _type(tester, 'legal', 'Fresh Company BV');
  await _type(tester, 'vat', 'be 0123.456.749');
  await _tap(tester, 'setup-next-button');
  await _type(tester, 'country', 'be');
  await _type(tester, 'currency', 'eur');
  await _tap(tester, 'setup-next-button');
  await _type(tester, 'email', 'boss@fresh.example');
  await _type(tester, 'adminName', 'The Boss');
  await _tap(tester, 'setup-next-button');
}

void main() {
  testWidgets('validates each step before going on', (tester) async {
    final http = FakeHttp({'GET /api/v1/setup/status': (_) => _status()});
    await _pump(tester, http);
    expect(find.text('Step 1 of 4'), findsOneWidget);
    await _tap(tester, 'setup-next-button');
    expect(find.text('Enter the company name.'), findsOneWidget);
    await _type(tester, 'name', 'Fresh Co');
    await _type(tester, 'vat', '!');
    await _tap(tester, 'setup-next-button');
    expect(
      find.text('A VAT number has 4 to 20 letters and digits.'),
      findsOneWidget,
    );
    await _type(tester, 'vat', '');
    await _tap(tester, 'setup-next-button');
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await _type(tester, 'country', 'B');
    await _type(tester, 'currency', 'EU');
    await _tap(tester, 'setup-next-button');
    expect(find.text('Enter a two-letter country code.'), findsOneWidget);
    expect(find.text('Enter a three-letter currency code.'), findsOneWidget);
    await _type(tester, 'country', 'be');
    await _type(tester, 'currency', 'eur');
    await _tap(tester, 'setup-next-button');

    await _type(tester, 'email', 'nobody');
    await _tap(tester, 'setup-next-button');
    expect(find.text('Enter a valid e-mail address.'), findsOneWidget);
    expect(find.text("Enter the administrator's name."), findsOneWidget);
    await _tap(tester, 'setup-back');
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('the token step exists only when the server asks for it', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/setup/status': (_) => _status(token: true),
    });
    await _pump(tester, http);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    await _fillAll(tester);
    expect(find.text('Step 4 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-token')), findsOneWidget);
    await _tap(tester, 'setup-next-button');
    expect(find.text('Enter the setup token.'), findsOneWidget);
    await _type(tester, 'token', 's3cret');
    await _tap(tester, 'setup-next-button');
    expect(find.byKey(const ValueKey('setup-create')), findsOneWidget);
  });

  testWidgets('creates the company and signs in as the admin in dev mode', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/setup/status': (_) => _status(),
      'POST /api/v1/setup/bootstrap': (_) => _created('dev'),
    });
    final c = await _pump(tester, http);
    await _fillAll(tester);
    expect(find.text('Step 4 of 4'), findsOneWidget);
    // The review shows what will be created.
    expect(find.text('Fresh Co'), findsOneWidget);
    expect(find.text('BE'), findsOneWidget);
    expect(find.text('boss@fresh.example'), findsOneWidget);
    await _tap(tester, 'setup-create');
    final sent = http.bodies['POST /api/v1/setup/bootstrap'] as Map;
    expect(sent['name'], 'Fresh Co');
    expect(sent['legal_name'], 'Fresh Company BV');
    expect(sent['vat_number'], 'be 0123.456.749');
    expect(sent['country_code'], 'BE');
    expect(sent['currency'], 'EUR');
    expect(sent['default_language'], 'en');
    expect(sent['admin_email'], 'boss@fresh.example');
    expect(sent.containsKey('token'), isFalse);
    final s = c.read(sessionProvider);
    expect(s.isSignedIn, isTrue);
    expect(s.devUser, 'boss@fresh.example');
  });

  testWidgets('with OIDC it explains how to sign in and does not sign in', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/setup/status': (_) => _status(token: true, mode: 'oidc'),
      'POST /api/v1/setup/bootstrap': (_) => _created('oidc'),
    });
    final c = await _pump(tester, http);
    await _fillAll(tester);
    await _type(tester, 'token', 's3cret');
    await _tap(tester, 'setup-next-button');
    await _tap(tester, 'setup-create');
    expect(
      http.bodies['POST /api/v1/setup/bootstrap'],
      containsPair('token', 's3cret'),
    );
    expect(find.text('Company Fresh Co created.'), findsOneWidget);
    expect(find.textContaining('identity provider'), findsOneWidget);
    expect(c.read(sessionProvider).isSignedIn, isFalse);
    await _tap(tester, 'setup-to-login');
    expect(find.byKey(const ValueKey('login-environments')), findsOneWidget);
  });

  for (final (code, text) in [
    (403, 'The setup token is missing or wrong.'),
    (404, 'Setting up is disabled on this server.'),
    (409, 'This server already has a company.'),
    (422, 'country_code must be two letters'),
  ]) {
    testWidgets('shows a $code answer clearly', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/setup/status': (_) => _status(),
        'POST /api/v1/setup/bootstrap': (_) => FakeStatus(code, {
          'error': 'x',
          'message': 'country_code must be two letters',
        }),
      });
      final c = await _pump(tester, http);
      await _fillAll(tester);
      await _tap(tester, 'setup-create');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('setup-error'))).data,
        contains(text),
      );
      expect(c.read(sessionProvider).isSignedIn, isFalse);
    });
  }

  testWidgets('the login page offers setup only when the server needs it', (
    tester,
  ) async {
    var needs = true;
    final http = FakeHttp({
      'GET /api/v1/setup/status': (_) => _status(needs: needs),
    });
    await _pump(tester, http, initial: '/login');
    expect(find.byKey(const ValueKey('login-setup')), findsOneWidget);
    // Changing the address makes the wizard target that server (after the debounce).
    await tester.enterText(
      find.widgetWithText(TextField, 'Server'),
      'http://localhost:9999',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('login-setup')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-setup')), findsOneWidget);
    await _tap(tester, 'login-setup');
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Server: http://localhost:9999'), findsOneWidget);

    needs = false;
    await _pump(tester, http, initial: '/login');
    expect(find.byKey(const ValueKey('login-setup')), findsNothing);
  });

  testWidgets('an unreachable server just means no offer on the login page', (
    tester,
  ) async {
    await _pump(tester, FakeHttp({}), initial: '/login');
    expect(find.byKey(const ValueKey('login-setup')), findsNothing);
  });

  testWidgets('never sends the token to a remote server over plain http', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/setup/status': (_) => _status(token: true),
      'POST /api/v1/setup/bootstrap': (_) => _created('dev'),
    });
    final c = await _pump(
      tester,
      http,
      session: const Session(serverUrl: 'http://erp.example.com'),
    );
    await _fillAll(tester);
    await _type(tester, 'token', 's3cret');
    await _tap(tester, 'setup-next-button');
    await _tap(tester, 'setup-create');
    expect(http.requests, isNot(contains('POST /api/v1/setup/bootstrap')));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('setup-error'))).data,
      contains('https://'),
    );
    expect(c.read(sessionProvider).isSignedIn, isFalse);
  });

  test('only https or loopback http counts as secure', () {
    for (final ok in [
      'https://erp.example.com',
      'http://localhost:8080',
      'http://127.0.0.1:8080',
      'http://127.1.2.3',
      'http://[::1]:8080',
    ]) {
      expect(isSecureServerUrl(ok), isTrue, reason: ok);
    }
    for (final bad in [
      'http://erp.example.com',
      'http://10.0.0.5:8080',
      'http://127.0.0.1.evil.com',
      'ftp://localhost',
      'localhost:8080',
      '',
    ]) {
      expect(isSecureServerUrl(bad), isFalse, reason: bad);
    }
  });

  testWidgets('a server that does not need setup shows no form', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/setup/status': (_) => _status(needs: false),
    });
    await _pump(tester, http);
    expect(find.byKey(const ValueKey('setup-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-name')), findsNothing);
    expect(find.byKey(const ValueKey('setup-create')), findsNothing);
    await _tap(tester, 'setup-unavailable-back');
    expect(find.byKey(const ValueKey('login-environments')), findsOneWidget);
  });

  testWidgets('names are limited to 200 characters', (tester) async {
    final http = FakeHttp({'GET /api/v1/setup/status': (_) => _status()});
    await _pump(tester, http);
    await _type(tester, 'legal', 'x' * 250);
    final legal = tester.widget<TextField>(
      find.byKey(const ValueKey('setup-legal')),
    );
    expect(legal.controller!.text.length, 200);
  });

  test('e-mail validation rejects empty domain labels', () {
    for (final ok in ['a@b.de', 'a.b@c.example.org']) {
      expect(SetupValidation.email(ok), isTrue, reason: ok);
    }
    for (final bad in [
      'a@b..de',
      'a@.b.de',
      'a@b.de.',
      'a@b',
      'a b@c.de',
      '@b.de',
    ]) {
      expect(SetupValidation.email(bad), isFalse, reason: bad);
    }
  });

  testWidgets('a redirect is not followed and the token is not re-sent', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/setup/status': (_) => _status(token: true),
      'POST /api/v1/setup/bootstrap': (_) => FakeStatus(307, {
        'location': 'http://evil.example/api/v1/setup/bootstrap',
      }),
    });
    final c = await _pump(tester, http);
    await _fillAll(tester);
    await _type(tester, 'token', 's3cret');
    await _tap(tester, 'setup-next-button');
    await _tap(tester, 'setup-create');
    expect(
      http.requests.where((r) => r == 'POST /api/v1/setup/bootstrap'),
      hasLength(1),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('setup-error'))).data,
      contains('redirected'),
    );
    expect(c.read(sessionProvider).isSignedIn, isFalse);
  });

  testWidgets('a slow setup answer for an older address is dropped', (
    tester,
  ) async {
    final slow = Completer<SetupStatusInfo>();
    final c = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
        environmentProbeProvider.overrideWithValue(_probe),
        setupStatusProvider.overrideWithValue(
          (url) => url == 'http://a.example'
              ? slow.future
              : Future.value(
                  const SetupStatusInfo(
                    needsSetup: false,
                    tokenRequired: false,
                    authMode: 'dev',
                  ),
                ),
        ),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Server');
    await tester.enterText(field, 'http://a.example');
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(field, 'http://b.example');
    await tester.pump(const Duration(seconds: 1));
    // The answer for the first address arrives after the address changed.
    slow.complete(
      const SetupStatusInfo(
        needsSetup: true,
        tokenRequired: false,
        authMode: 'dev',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-setup')), findsNothing);
  });
}
