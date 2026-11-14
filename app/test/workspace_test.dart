import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/detail_routes.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

/// A stand-in detail screen with state worth keeping: a text field. It reports whether its tab is
/// focused, and can push another screen and pop a result, like a ticket opening a quotation.
class _Probe extends StatefulWidget {
  const _Probe(this.name);
  final String name;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _text = TextEditingController();
  String? result;

  @override
  Widget build(BuildContext context) {
    final active = TabScope.activeOf(context);
    return Scaffold(
      body: Column(
        children: [
          Text('${widget.name} active=$active result=$result'),
          TextField(key: ValueKey('field-${widget.name}'), controller: _text),
          TextButton(
            onPressed: () async {
              final r = await context.push<String>('/orders/${widget.name}-in');
              setState(() => result = r);
            },
            child: Text('push-${widget.name}'),
          ),
          TextButton(
            onPressed: () => context.pop('result-${widget.name}'),
            child: Text('pop-${widget.name}'),
          ),
          TextButton(
            onPressed: () => context.go('/orders'),
            child: Text('back-${widget.name}'),
          ),
        ],
      ),
    );
  }
}

Widget? _probes(Uri uri) =>
    isDetailLocation(uri.toString()) ? _Probe(uri.pathSegments.last) : null;

void main() {
  late GoRouter router;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    double width = 1400,
    MemoryKvStore? kv,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final http = FakeHttp({
      'GET /api/v1/me': (_) =>
          meJson(['orders.read', 'helpdesk.read', 'quotations.read']),
    });
    router = GoRouter(
      initialLocation: '/orders',
      routes: [
        ShellRoute(
          builder: (c, s, child) =>
              AppShell(location: s.matchedLocation, child: child),
          routes: [
            GoRoute(
              path: '/orders',
              builder: (_, _) => Column(
                children: [
                  const Text('ORDERS LIST'),
                  Builder(
                    builder: (c) => TextButton(
                      onPressed: () => c.push('/orders/o1'),
                      child: const Text('open-o1'),
                    ),
                  ),
                ],
              ),
            ),
            GoRoute(
              path: '/orders/:id',
              builder: (_, s) => DetailPortal(location: s.uri.toString()),
            ),
            GoRoute(
              path: '/helpdesk',
              builder: (_, _) => const Text('HELPDESK LIST'),
            ),
          ],
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(kv ?? MemoryKvStore()),
        detailScreenProvider.overrideWithValue(_probes),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  WorkspaceNotifier ws(ProviderContainer c) =>
      c.read(workspaceProvider.notifier);

  ProviderContainer plain([MemoryKvStore? kv]) {
    final c = ProviderContainer(
      overrides: [kvStoreProvider.overrideWithValue(kv ?? MemoryKvStore())],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('workspace model', () {
    test('open focuses an existing tab instead of adding a second', () {
      final c = plain();
      final n = c.read(workspaceProvider.notifier);
      final a = n.open('/orders/a');
      final b = n.open('/orders/b', focus: false);
      expect(c.read(workspaceProvider).active, a);
      expect(n.open('/orders/b'), b);
      expect(c.read(workspaceProvider).tabs, hasLength(2));
      expect(c.read(workspaceProvider).active, b);
    });

    test('closing the active tab focuses a neighbour, then the main area', () {
      final c = plain();
      final n = c.read(workspaceProvider.notifier);
      final a = n.open('/orders/a');
      final b = n.open('/orders/b');
      n.close(b);
      expect(c.read(workspaceProvider).active, a);
      n.close(a);
      expect(c.read(workspaceProvider).active, isNull);
      expect(c.read(workspaceProvider).tabs, isEmpty);
    });

    test('detail locations are told from lists and settings pages', () {
      for (final l in [
        '/helpdesk/t1',
        '/quotations/new?customer=c1',
        '/quotations/q1',
        '/orders/o1',
        '/repairs/r1',
        '/jobs/j1',
        '/jobs/contracts/c1',
        '/products/p1',
        '/opportunities/o1',
        '/stock/products/p1',
        '/stock/counts/c1',
        '/kb/k1',
      ]) {
        expect(isDetailLocation(l), isTrue, reason: l);
      }
      for (final l in [
        '/helpdesk',
        '/helpdesk/settings',
        '/helpdesk/reports',
        '/kb/categories',
        '/repairs/departments',
        '/jobs/contracts',
        '/jobs/equipment/c1',
        '/stock/warehouses',
        '/orders',
      ]) {
        expect(isDetailLocation(l), isFalse, reason: l);
      }
    });

    test('tabs are restored from the same store only', () async {
      final kv = MemoryKvStore();
      final c1 = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(kv)],
      );
      c1.read(workspaceProvider.notifier)
        ..open('/orders/a')
        ..open('/helpdesk/t1', focus: false);
      c1.dispose();

      final c2 = plain(kv);
      c2.read(workspaceProvider);
      await Future<void>.delayed(Duration.zero);
      final s = c2.read(workspaceProvider);
      expect(s.tabs.map((t) => t.location), ['/orders/a', '/helpdesk/t1']);
      expect(s.activeTab?.location, '/orders/a');

      final c3 = plain();
      c3.read(workspaceProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c3.read(workspaceProvider).tabs, isEmpty);
    });
  });

  group('tab strip and navigators', () {
    testWidgets('go replaces the whole stack and the tab follows the new top', (
      tester,
    ) async {
      final c = await pump(tester);
      ws(c).open('/orders/a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('push-a'));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('pop-a-in'))).go('/orders/x');
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs.single.location, '/orders/x');
      // The replaced screens are gone: popping has nothing left to return to.
      expect(find.text('pop-x'), findsOneWidget);
      expect(GoRouter.of(tester.element(find.text('pop-x'))).canPop(), isFalse);
    });

    testWidgets('pushReplacement swaps the top route in place', (tester) async {
      final c = await pump(tester);
      ws(c).open('/orders/a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('push-a'));
      await tester.pumpAndSettle();
      unawaited(
        GoRouter.of(tester.element(find.text('pop-a-in')))
            .pushReplacement('/orders/z'),
      );
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs.single.location, '/orders/z');
      await tester.tap(find.text('pop-z'));
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs.single.location, '/orders/a');
    });

    testWidgets('leaving a dirty tab asks first and keeps it on cancel', (
      tester,
    ) async {
      final c = await pump(tester);
      final id = ws(c).open('/orders/a');
      await tester.pumpAndSettle();
      ws(c).dirtyOf(id).value = true;
      await tester.tap(find.text('back-a'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs, hasLength(1));
      expect(ws(c).state.active, id);
      expect(find.textContaining('a active=true'), findsOneWidget);

      await tester.tap(find.text('back-a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs, isEmpty);
      expect(find.text('ORDERS LIST'), findsOneWidget);
    });

    testWidgets('leaving a clean tab closes it without asking', (tester) async {
      final c = await pump(tester);
      ws(c).open('/orders/a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('back-a'));
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs, isEmpty);
      expect(find.text('ORDERS LIST'), findsOneWidget);
    });

    testWidgets('a tab chip keeps its close button and unsaved marker in '
        'the semantics', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(MemoryKvStore())],
      );
      addTearDown(c.dispose);
      final id = ws(c).open('/orders/a');
      ws(c).dirtyOf(id).value = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: WorkspaceTabStrip()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The chip's own label and selected state stay ...
      final chip = tester.getSemantics(find.bySemanticsLabel('Order a'));
      expect(chip.getSemanticsData().flagsCollection.isSelected.name, 'isTrue');
      // ... and so do the unsaved marker and the close button below it.
      expect(find.bySemanticsLabel('Unsaved changes'), findsOneWidget);
      final close = tester.getSemantics(find.byTooltip('Close tab'));
      expect(close.getSemanticsData().tooltip, 'Close tab');
      handle.dispose();
    });

    testWidgets('a detail link opens a tab and leaves the list in place', (
      tester,
    ) async {
      final c = await pump(tester);
      await tester.tap(find.text('open-o1'));
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs.map((t) => t.location), ['/orders/o1']);
      expect(ws(c).state.active, isNotNull);
      expect(router.state.matchedLocation, '/orders');
      expect(find.byKey(const ValueKey('tab-home')), findsOneWidget);
      expect(find.textContaining('o1 active=true'), findsOneWidget);
    });

    testWidgets('the tab strip and the rail stay in the semantics tree with a record open', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await tester.tap(find.text('open-o1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('o1 active=true'), findsOneWidget);
      // The modal barrier of the tab's page route blocks the semantics of whatever was painted before it;
      // without a semantic boundary around the tab's navigator that reached the shell around it.
      expect(find.bySemanticsLabel('Overview'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Helpdesk')), findsWidgets);
      handle.dispose();
    });

    testWidgets('opening the same location again focuses the same tab', (
      tester,
    ) async {
      final c = await pump(tester);
      final id = ws(c).open('/orders/o1');
      ws(c).focusHome();
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-o1'));
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs, hasLength(1));
      expect(ws(c).state.active, id);
    });

    testWidgets('closing a tab with the close button removes it', (
      tester,
    ) async {
      final c = await pump(tester);
      final id = ws(c).open('/orders/o1');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('tab-$id')),
          matching: find.byTooltip('Close tab'),
        ),
      );
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs, isEmpty);
      expect(find.text('ORDERS LIST'), findsOneWidget);
    });

    testWidgets('a middle click on a tab closes it', (tester) async {
      final c = await pump(tester);
      final id = ws(c).open('/orders/o1');
      await tester.pumpAndSettle();
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('tab-$id'))),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await g.up();
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs, isEmpty);
    });

    testWidgets('screens keep their state while another tab is shown', (
      tester,
    ) async {
      final c = await pump(tester);
      final a = ws(c).open('/orders/a');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-a')), 'draft');
      final b = ws(c).open('/orders/b');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('a active=false', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.textContaining('b active=true'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('tab-$a')));
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
      expect(
        find.textContaining('b active=false', skipOffstage: false),
        findsOneWidget,
      );
      expect(ws(c).state.active, a);
      expect(a, isNot(b));

      // And through the main area and back.
      ws(c).focusHome();
      await tester.pumpAndSettle();
      expect(find.text('ORDERS LIST'), findsOneWidget);
      ws(c).focus(a);
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
    });

    testWidgets('push stays in the tab and pop returns its result', (
      tester,
    ) async {
      final c = await pump(tester);
      ws(c).open('/orders/a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('push-a'));
      await tester.pumpAndSettle();
      // The pushed screen is in the same tab, not a new one.
      expect(ws(c).state.tabs, hasLength(1));
      expect(ws(c).state.tabs.single.location, '/orders/a-in');
      await tester.tap(find.text('pop-a-in'));
      await tester.pumpAndSettle();
      expect(find.textContaining('result=result-a-in'), findsOneWidget);
      expect(ws(c).state.tabs.single.location, '/orders/a');
    });

    testWidgets('going back to a list closes the tab and shows the list', (
      tester,
    ) async {
      final c = await pump(tester);
      ws(c).open('/orders/a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('back-a'));
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs, isEmpty);
      expect(find.text('ORDERS LIST'), findsOneWidget);
    });

    testWidgets('a tab restored in the background builds only when shown', (
      tester,
    ) async {
      final kv = MemoryKvStore();
      final first = plain(kv);
      first.read(workspaceProvider.notifier)
        ..open('/orders/a', focus: false)
        ..open('/orders/b', focus: false);
      first.dispose();
      final c = await pump(tester, kv: kv);
      await tester.pumpAndSettle();
      expect(ws(c).state.tabs, hasLength(2));
      expect(find.textContaining('active=', skipOffstage: false), findsNothing);
      ws(c).focus(ws(c).state.tabs.last.id);
      await tester.pumpAndSettle();
      expect(find.textContaining('b active=true'), findsOneWidget);
    });
  });

  testWidgets('narrow layout offers the tabs in an app bar menu', (
    tester,
  ) async {
    final c = await pump(tester, width: 500);
    expect(find.byKey(const ValueKey('tab-menu')), findsNothing);
    final id = ws(c).open('/orders/o1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tab-home')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'Overview'),
    );
    await tester.pumpAndSettle();
    expect(ws(c).state.active, isNull);
    expect(ws(c).state.tabs.single.id, id);
  });

  testWidgets('closing a tab with unsaved edits asks first', (tester) async {
    final c = await pump(tester);
    final id = ws(c).open('/orders/o1');
    await tester.pumpAndSettle();
    ws(c).dirtyOf(id).value = true;
    await tester.pump();
    Finder closeButton() => find.descendant(
      of: find.byKey(ValueKey('tab-$id')),
      matching: find.byTooltip('Close tab'),
    );
    await tester.tap(closeButton());
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ws(c).state.tabs, hasLength(1));

    await tester.tap(closeButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(ws(c).state.tabs, isEmpty);
  });
}
