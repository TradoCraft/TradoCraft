import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/admin/admin_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _user(
  String id,
  String name, {
  List<String> roles = const ['sales'],
  List<String> disabled = const [],
  bool active = true,
  bool signedIn = true,
}) => {
  'user_id': id,
  'email': '$id@example.com',
  'display_name': name,
  'roles': roles,
  'disabled_modules': disabled,
  'active': active,
  'has_signed_in': signedIn,
};

Map<String, Object?> _module(
  String code, {
  bool enabled = true,
  List<String> requires = const [],
}) => {
  'code': code,
  'enabled': enabled,
  'permissions': <String>[],
  'requires': requires,
};

List<Object?> _modules() => [
  _module('customers'),
  _module('products', enabled: false),
  _module('sales', requires: ['customers', 'products']),
  _module('helpdesk'),
];

List<Object?> _roles() => [
  {
    'role': 'admin',
    'permissions': ['a', 'b', 'c'],
  },
  {
    'role': 'sales',
    'permissions': ['a'],
  },
  {'role': 'viewer', 'permissions': <String>[]},
];

Map<String, Object? Function(Object?)> _routes({
  Map<String, Object? Function(Object?)>? extra,
}) => {
  'GET /api/v1/me': (_) => {
    ...meJson(['users.admin']),
    'user_id': 'me',
  },
  'GET /api/v1/admin/users': (_) => [
    _user('me', 'Ada Admin', roles: ['admin']),
    _user('u2', 'Sam Sales', disabled: ['helpdesk'], signedIn: false),
    _user('u3', 'Old Timer', active: false),
  ],
  'GET /api/v1/admin/modules': (_) => _modules(),
  'GET /api/v1/roles': (_) => _roles(),
  ...?extra,
};

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          // The shell watches /me; the test stands in for it.
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(meProvider);
              return home;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openUser(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

FilterChip _chip(WidgetTester tester, String role) =>
    tester.widget<FilterChip>(find.byKey(ValueKey('role-$role')));

void main() {
  testWidgets('the users list shows names, roles, modules and status', (
    tester,
  ) async {
    await _pump(tester, FakeHttp(_routes()), const AdminPage());
    expect(find.text('Ada Admin'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('Sam Sales'), findsOneWidget);
    expect(find.text('Helpdesk'), findsOneWidget);
    expect(find.text('Not signed in yet'), findsOneWidget);
    expect(find.text('inactive'), findsOneWidget);

    // Filter on deactivated members.
    await tester.tap(find.text('All members'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivated members').last);
    await tester.pumpAndSettle();
    expect(find.text('Old Timer'), findsOneWidget);
    expect(find.text('Sam Sales'), findsNothing);
  });

  testWidgets('creating a user posts the form and shows a 409', (tester) async {
    var conflict = true;
    final http = FakeHttp(
      _routes(
        extra: {
          'POST /api/v1/admin/users': (_) => conflict
              ? FakeStatus(409, {
                  'error': 'conflict',
                  'message': 'already a member',
                })
              : _user('new', 'New Person', roles: ['sales', 'viewer']),
        },
      ),
    );
    await _pump(tester, http, const AdminPage());
    await tester.tap(find.text('New user'));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'new@example.com');
    await tester.enterText(fields.at(1), 'New Person');
    await tester.tap(find.byKey(const ValueKey('role-sales')));
    await tester.tap(find.byKey(const ValueKey('role-viewer')));
    await tester.tap(find.byKey(const ValueKey('module-helpdesk')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(http.bodies['POST /api/v1/admin/users'], {
      'email': 'new@example.com',
      'display_name': 'New Person',
      'roles': ['sales', 'viewer'],
      'disabled_modules': ['helpdesk'],
    });
    expect(find.text('already a member'), findsOneWidget);
    expect(find.text('New user'), findsWidgets); // dialog still open

    conflict = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('role chips toggle and save the chosen roles', (tester) async {
    final http = FakeHttp(
      _routes(
        extra: {
          'PUT /api/v1/admin/users/u2': (_) =>
              _user('u2', 'Sam Sales', roles: ['viewer']),
        },
      ),
    );
    await _pump(tester, http, const AdminPage());
    await _openUser(tester, 'Sam Sales');
    expect(_chip(tester, 'sales').selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('role-sales')));
    await tester.tap(find.byKey(const ValueKey('role-viewer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(http.bodies['PUT /api/v1/admin/users/u2'], {
      'active': true,
      'disabled_modules': ['helpdesk'],
      'display_name': 'Sam Sales',
      'roles': ['viewer'],
    });
  });

  testWidgets('a module the company switched off is greyed out for the user', (
    tester,
  ) async {
    await _pump(tester, FakeHttp(_routes()), const AdminPage());
    await _openUser(tester, 'Sam Sales');
    final products = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('module-products')),
    );
    expect(products.onChanged, isNull);
    expect(products.value, isFalse);
    expect(find.textContaining('Switched off for the whole company'), findsOne);
    expect(find.textContaining('Needs Customers, Products'), findsOneWidget);
    final helpdesk = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('module-helpdesk')),
    );
    expect(helpdesk.onChanged, isNotNull);
    expect(helpdesk.value, isFalse); // disabled for this user
  });

  testWidgets('your own row cannot be deactivated or lose the admin role', (
    tester,
  ) async {
    await _pump(tester, FakeHttp(_routes()), const AdminPage());
    await _openUser(tester, 'Ada Admin');
    expect(_chip(tester, 'admin').onSelected, isNull);
    expect(_chip(tester, 'viewer').onSelected, isNotNull);
    final active = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('active')),
    );
    expect(active.onChanged, isNull);
    expect(find.text('You cannot deactivate yourself.'), findsOneWidget);
  });

  testWidgets('someone who has not signed in can be invited again', (
    tester,
  ) async {
    final http = FakeHttp(
      _routes(extra: {'POST /api/v1/admin/users/u2/invite': (_) => null}),
    );
    await _pump(tester, http, const AdminPage());
    await _openUser(tester, 'Ada Admin');
    expect(find.text('Send invitation again'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _openUser(tester, 'Sam Sales');
    await tester.tap(find.text('Send invitation again'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/admin/users/u2/invite'));
    expect(find.text('Invitation sent'), findsOneWidget);
  });

  testWidgets('the modules page saves switches and shows the 422 message', (
    tester,
  ) async {
    var reject = true;
    final http = FakeHttp(
      _routes(
        extra: {
          'PUT /api/v1/admin/modules': (_) => reject
              ? FakeStatus(422, {
                  'error': 'validation',
                  'message': 'sales requires customers',
                })
              : _modules(),
        },
      ),
    );
    await _pump(tester, http, const AdminPage());
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();
    expect(find.text('Needs Customers, Products'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('module-customers')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Switching customers off takes sales (which requires it) along.
    expect(http.bodies['PUT /api/v1/admin/modules'], {
      'disabled_modules': ['customers', 'products', 'sales'],
    });
    expect(find.text('sales requires customers'), findsOneWidget);

    reject = false;
    await tester.pump(
      const Duration(seconds: 10),
    ); // let the error snack bar go
    await tester.pumpAndSettle();
    final before = http.requests.where((r) => r == 'GET /api/v1/me').length;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Modules saved'), findsOneWidget);
    // The nav depends on /me, so it is fetched again after saving.
    expect(
      http.requests.where((r) => r == 'GET /api/v1/me').length,
      greaterThan(before),
    );
  });

  group('module tree', () {
    List<Object?> tree({List<String> off = const []}) => [
      for (final m in [
        ('customers', <String>[]),
        ('products', <String>[]),
        ('sales', ['customers', 'products']),
        ('delivery', ['sales', 'products']),
        ('helpdesk', <String>[]),
      ])
        _module(m.$1, requires: m.$2, enabled: !off.contains(m.$1)),
    ];

    Future<FakeHttp> open(
      WidgetTester tester, {
      List<String> off = const [],
    }) async {
      final http = FakeHttp(
        _routes(
          extra: {
            'GET /api/v1/admin/modules': (_) => tree(off: off),
            'PUT /api/v1/admin/modules': (_) => tree(),
          },
        ),
      );
      await _pump(tester, http, const AdminPage());
      await tester.tap(find.text('Modules'));
      await tester.pumpAndSettle();
      return http;
    }

    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('shows roots, children and repeated multi-parent modules', (
      tester,
    ) async {
      await open(tester);
      for (final k in [
        'module-customers',
        'module-products',
        'module-helpdesk',
        'module-sales',
        'module-delivery',
        'module-sales-under-products',
        'module-delivery-under-products',
      ]) {
        expect(key(k), findsOneWidget, reason: k);
      }
      expect(find.text('Needs Customers, Products'), findsOneWidget);
      expect(find.text('Also needs Customers'), findsOneWidget);
      expect(find.text('Also needs Sales'), findsOneWidget);
      // Indentation: children sit to the right of their parent.
      expect(
        tester.getTopLeft(key('module-sales')).dx,
        greaterThan(tester.getTopLeft(key('module-customers')).dx),
      );
    });

    testWidgets(
      'switching off cascades, says so, and saves the effective set',
      (tester) async {
        final http = await open(tester);
        await tester.tap(key('module-customers'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Also switches off: Sales'), findsOneWidget);
        // customers, sales (x2) and delivery (x2) read Off; both occurrences share state.
        expect(find.text('Off'), findsNWidgets(5));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(http.bodies['PUT /api/v1/admin/modules'], {
          'disabled_modules': ['customers', 'delivery', 'sales'],
        });
      },
    );

    testWidgets('switching on enables what the module needs', (tester) async {
      await open(tester, off: ['customers', 'sales', 'delivery']);
      await tester.tap(key('module-delivery'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Also switches on: '), findsOneWidget);
      expect(find.text('Off'), findsNothing);
    });

    testWidgets('a repeated occurrence toggles the same state', (tester) async {
      await open(tester);
      await tester.tap(key('module-sales-under-products'));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(key('module-sales')).value, false);
      expect(
        tester.widget<SwitchListTile>(key('module-delivery')).value,
        false,
      );
    });

    testWidgets('rows collapse and expand', (tester) async {
      await open(tester);
      await tester.tap(key('expand-customers'));
      await tester.pumpAndSettle();
      expect(key('module-sales'), findsNothing);
      expect(key('module-delivery'), findsNothing);
      expect(key('module-sales-under-products'), findsOneWidget);
      await tester.tap(key('expand-customers'));
      await tester.pumpAndSettle();
      expect(key('module-sales'), findsOneWidget);
    });
  });

  group('navigation', () {
    Future<void> shell(WidgetTester tester, List<String> perms) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(perms),
        'GET /api/v1/admin/users': (_) => [],
        'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
      });
      final router = GoRouter(
        initialLocation: '/admin',
        routes: [
          ShellRoute(
            builder: (c, s, child) =>
                AppShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(path: '/admin', builder: (_, _) => const Text('ADMIN')),
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
          overrides: [dioProvider.overrideWithValue(fakeDio(http))],
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

    testWidgets('the Administration destination needs users.admin', (
      tester,
    ) async {
      await shell(tester, ['users.admin', 'quotations.read']);
      expect(find.text('Administration'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('prices.write alone reaches the Administration destination', (
      tester,
    ) async {
      await shell(tester, ['prices.write']);
      expect(find.text('Administration'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('without users.admin it disappears and the redirect works', (
      tester,
    ) async {
      await shell(tester, ['quotations.read']);
      expect(find.text('Administration'), findsNothing);
      expect(find.text('QUOTES'), findsOneWidget);
    });
  });

  testWidgets('prices.write without users.admin sees only the price zones', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['prices.write']),
      'GET /api/v1/price-zones': (_) => [],
    });
    await _pump(tester, http, const AdminPage());
    expect(find.text('Users'), findsNothing);
    expect(find.text('Modules'), findsNothing);
    expect(find.text('Price zones'), findsOneWidget);
    expect(http.requests, isNot(contains('GET /api/v1/admin/users')));
  });

  testWidgets('can() follows the permissions of /me', (tester) async {
    Future<bool> check(List<String> perms) async {
      bool? seen;
      final http = FakeHttp({'GET /api/v1/me': (_) => meJson(perms)});
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [dioProvider.overrideWithValue(fakeDio(http))],
          child: Consumer(
            builder: (context, ref, _) {
              seen = can(ref, 'users.admin');
              return const SizedBox();
            },
          ),
        ),
      );
      final first = seen; // while loading
      await tester.pumpAndSettle();
      expect(first, isFalse);
      return seen!;
    }

    expect(await check(['users.admin']), isTrue);
    expect(await check(['orders.read']), isFalse);
  });
}
