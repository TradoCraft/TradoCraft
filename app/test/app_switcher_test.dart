import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/detail_routes.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/core/navigation/app_groups.dart';
import 'package:tradocraft_app/core/navigation/breadcrumbs.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

class _Detail extends StatelessWidget {
  const _Detail({required this.sub});
  final bool sub;

  @override
  Widget build(BuildContext context) {
    TabScope.reportTitle(context, 'O-100');
    if (sub) {
      Breadcrumbs.report(context, const [Crumb('O-100'), Crumb('Lines')]);
    }
    return const Text('DETAIL');
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  List<String> perms, {
  bool wide = true,
  String start = '/orders',
  bool sub = false,
}) async {
  tester.view.physicalSize = wide
      ? const Size(1400, 1000)
      : const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final http = FakeHttp({'GET /api/v1/me': (_) => meJson(perms)});
  Widget list(String t) => Builder(
    builder: (c) =>
        TextButton(onPressed: () => c.push('/orders/o1'), child: Text(t)),
  );
  final router = GoRouter(
    initialLocation: start,
    routes: [
      ShellRoute(
        builder: (c, s, child) =>
            AppShell(location: s.matchedLocation, child: child),
        routes: [
          for (final p in [
            '/orders',
            '/quotations',
            '/opportunities',
            '/helpdesk',
            '/kb',
            '/customers',
            '/products',
            '/reports',
          ])
            GoRoute(path: p, builder: (_, _) => list('LIST $p')),
          GoRoute(
            path: '/orders/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
        ],
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(fakeDio(http)),
      kvStoreProvider.overrideWithValue(MemoryKvStore()),
      detailScreenProvider.overrideWithValue(
        (uri) => isDetailLocation(uri.toString()) ? _Detail(sub: sub) : null,
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  return container;
}

const _perms = [
  'orders.read',
  'quotations.read',
  'helpdesk.read',
  'kb.read',
  'customers.read',
  'products.read',
];

final _switcher = find.byKey(const ValueKey('app-switcher'));

Future<void> _openSwitcher(WidgetTester tester) async {
  await tester.tap(_switcher);
  await tester.pumpAndSettle();
}

void main() {
  test('groups are visible when one of their paths is permitted', () {
    expect(visibleGroups(['/orders']).map((g) => g.id), ['sales']);
    expect(visibleGroups(['/kb', '/customers']).map((g) => g.id), [
      'service',
      'master',
    ]);
    expect(visibleGroups(const []), isEmpty);
    expect(groupOfPath('/configurator/builder')?.id, 'sales');
    expect(groupOfPath('/nowhere'), isNull);
  });

  testWidgets('the switcher lists only groups the user may use', (
    tester,
  ) async {
    await _pump(tester, _perms);
    await _openSwitcher(tester);
    expect(find.byKey(const ValueKey('app-group-sales')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-group-service')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-group-master')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-group-operations')), findsNothing);
    expect(find.byKey(const ValueKey('app-group-insight')), findsNothing);
  });

  testWidgets('the rail shows the active group; choosing another switches', (
    tester,
  ) async {
    await _pump(tester, _perms);
    final rail = find.byType(NavigationRail);
    expect(
      find.descendant(of: rail, matching: find.text('Orders')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Quotations')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Helpdesk')),
      findsNothing,
    );
    await _openSwitcher(tester);
    await tester.tap(find.byKey(const ValueKey('app-group-service')));
    await tester.pumpAndSettle();
    expect(find.text('LIST /helpdesk'), findsOneWidget);
    expect(
      find.descendant(of: rail, matching: find.text('Helpdesk')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Orders')),
      findsNothing,
    );
  });

  testWidgets('a group with one permitted entry falls back to the flat list', (
    tester,
  ) async {
    await _pump(tester, [
      'orders.read',
      'quotations.read',
      'helpdesk.read',
      'customers.read',
    ], start: '/helpdesk');
    final rail = find.byType(NavigationRail);
    expect(
      find.descendant(of: rail, matching: find.text('Orders')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Customers')),
      findsOneWidget,
    );
  });

  testWidgets('no switcher button for a single group', (tester) async {
    await _pump(tester, ['orders.read', 'quotations.read']);
    expect(_switcher, findsNothing);
  });

  testWidgets(
    'breadcrumbs show section and record; the section crumb goes back',
    (tester) async {
      final c = await _pump(tester, _perms);
      expect(find.byKey(const ValueKey('breadcrumbs')), findsNothing);
      await tester.tap(find.text('LIST /orders'));
      await tester.pumpAndSettle();
      expect(c.read(workspaceProvider).activeTab, isNotNull);
      final bar = find.byKey(const ValueKey('breadcrumbs'));
      expect(
        find.descendant(of: bar, matching: find.text('Orders')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('O-100')),
        findsOneWidget,
      );
      await tester.tap(find.descendant(of: bar, matching: find.text('Orders')));
      await tester.pumpAndSettle();
      expect(c.read(workspaceProvider).activeTab, isNull);
      expect(bar, findsNothing);
    },
  );

  testWidgets('a screen can report a longer trail', (tester) async {
    await _pump(tester, _perms, sub: true);
    await tester.tap(find.text('LIST /orders'));
    await tester.pumpAndSettle();
    final bar = find.byKey(const ValueKey('breadcrumbs'));
    expect(
      find.descendant(of: bar, matching: find.text('Lines')),
      findsOneWidget,
    );
  });

  testWidgets(
    'narrow layout: bottom bar of the active group, switcher in the app bar',
    (tester) async {
      await _pump(tester, _perms, wide: false);
      final bar = find.byType(NavigationBar);
      expect(
        find.descendant(of: bar, matching: find.text('Orders')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('Helpdesk')),
        findsNothing,
      );
      await _openSwitcher(tester);
      await tester.tap(find.byKey(const ValueKey('app-group-master')));
      await tester.pumpAndSettle();
      expect(find.text('LIST /customers'), findsOneWidget);
    },
  );

  testWidgets('wide rail shows active group label below the switcher button', (
    tester,
  ) async {
    await _pump(tester, _perms, wide: true, start: '/orders');
    final rail = find.byType(NavigationRail);
    expect(find.descendant(of: rail, matching: find.text('Sales')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-switcher')), findsOneWidget);
  });

  testWidgets('wide shell shows top-bar search trigger and opens global search', (
    tester,
  ) async {
    await _pump(tester, _perms, wide: true, start: '/orders');
    final trigger = find.byKey(const ValueKey('top-bar-search'));
    expect(trigger, findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('global-search-field')), findsOneWidget);
  });
}
