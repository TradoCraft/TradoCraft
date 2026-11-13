import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/detail_routes.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/shortcuts/host.dart';
import 'package:tradocraft_app/app/shortcuts/registry.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/customers/customers_page.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/orders/order_screen.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/features/todo/current_context.dart';
import 'package:tradocraft_app/features/todo/object_todos_button.dart';
import 'package:tradocraft_app/features/todo/todo_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _item(
  String id,
  String title, {
  String? linkKind,
  String? linkId,
  String? linkLabel,
  String? linkLocation,
  bool done = false,
}) => {
  'id': id,
  'parent_id': null,
  'position': 0,
  'title': title,
  'notes': '',
  'owner_id': 'u1',
  'owner_name': 'Me',
  'assignee_id': null,
  'assignee_name': null,
  'created_by': 'u1',
  'mine': true,
  'due_date': null,
  'done': done,
  'done_at': null,
  'done_by': null,
  'link_kind': linkKind,
  'link_id': linkId,
  'link_label': linkLabel,
  'link_location': linkLocation,
  'client_id': null,
  'created_at': '2027-02-02T09:00:00Z',
  'updated_at': '2027-02-02T09:00:00Z',
};

/// A detail screen of the harness: names its location, reports a title like a real screen and
/// carries the to-dos button of a quotation.
class _Detail extends StatefulWidget {
  const _Detail(this.uri);
  final Uri uri;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  @override
  void initState() {
    super.initState();
    TabScope.reportTitle(context, 'T-${widget.uri.pathSegments.last}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('detail ${widget.uri.path}'),
        ObjectTodosButton(
          kind: TodoLinkKind.quotation,
          id: widget.uri.pathSegments.last,
          label: 'T-${widget.uri.pathSegments.last}',
        ),
      ],
    ),
  );
}

Widget? _probes(Uri uri) =>
    isDetailLocation(uri.toString()) ? _Detail(uri) : null;

const _perms = ['orders.read', 'quotations.read', 'customers.read', 'todo.use'];

void main() {
  late ProviderContainer container;
  late FakeHttp http;
  late List<Map<String, Object?>> items;

  Future<void> pump(
    WidgetTester tester, {
    List<String> perms = _perms,
    String initial = '/orders',
    bool realScreens = false,
    Map<String, Object? Function(Object?)> routes = const {},
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/todo/items': (_) => items,
      'POST /api/v1/todo/items': (b) {
        final body = b as Map;
        final item = _item(
          'new${items.length}',
          body['title'] as String,
          linkKind: body['link_kind'] as String?,
          linkId: body['link_id'] as String?,
        );
        items.add(item);
        return FakeStatus(201, item);
      },
      'POST /api/v1/todo/items/a/complete': (_) {
        items.first['done'] = true;
        items.removeAt(0);
        return _item('a', 'x', done: true);
      },
      'PATCH /api/v1/todo/items/a': (_) => _item('a', 'Call'),
      ...routes,
    });
    container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
        if (!realScreens) detailScreenProvider.overrideWithValue(_probes),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      observers: [
        ModalShortcutObserver(container.read(shortcutRegistryProvider)),
      ],
      initialLocation: initial,
      routes: [
        ShellRoute(
          observers: [
            ModalShortcutObserver(container.read(shortcutRegistryProvider)),
          ],
          builder: (c, s, child) =>
              AppShell(location: s.matchedLocation, child: child),
          routes: [
            GoRoute(
              path: '/orders',
              builder: (_, _) => const Text('ORDERS LIST'),
            ),
            GoRoute(path: '/todo', builder: (_, _) => const TodoPage()),
            GoRoute(
              path: '/customers',
              builder: (_, _) => const CustomersPage(),
            ),
            for (final p in const [
              '/quotations/:id',
              '/orders/:id',
              '/customers/:id',
            ])
              GoRoute(
                path: p,
                builder: (_, s) => DetailPortal(location: s.uri.toString()),
              ),
          ],
        ),
      ],
    );
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
          builder: (context, child) => ShortcutsHost(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<bool> newTodoChord(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    return handled;
  }

  WorkspaceNotifier ws() => container.read(workspaceProvider.notifier);
  Finder key(String k) => find.byKey(ValueKey(k));

  /// Focuses a tab on [location] with the title its screen reports.
  Future<void> openTab(WidgetTester tester, String location) async {
    ws().open(location);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String title) async {
    await tester.enterText(key('todo-title-field'), title);
    await tester.tap(key('todo-dialog-save'));
    await tester.pumpAndSettle();
  }

  setUp(() => items = []);

  group('current context', () {
    testWidgets('a focused tab is the context, with the title it reports', (
      t,
    ) async {
      await pump(t);
      await openTab(t, '/quotations/q1');
      final c = container.read(currentContextProvider);
      expect(c.location, '/quotations/q1');
      expect(c.title, 'T-q1');
      expect(c.target!.ref.kind, TodoLinkKind.quotation);
      expect(c.target!.ref.id, 'q1');
      expect(c.target!.label, 'T-q1');
      expect(c.target!.location, '/quotations/q1');
    });

    testWidgets('a list page has no object; the main area is its location', (
      t,
    ) async {
      await pump(t);
      final c = container.read(currentContextProvider);
      expect(c.location, '/orders');
      expect(c.target, isNull);
    });

    testWidgets(
      'a tab that is not a record (a new quotation) is not linkable',
      (t) async {
        await pump(t);
        await openTab(t, '/quotations/new');
        expect(container.read(currentContextProvider).target, isNull);
      },
    );

    testWidgets('back in the main area the tab no longer counts', (t) async {
      await pump(t);
      await openTab(t, '/quotations/q1');
      ws().focusHome();
      await t.pumpAndSettle();
      expect(container.read(currentContextProvider).target, isNull);
    });
  });

  group('quick add', () {
    testWidgets('from a focused tab it links to the record by default', (
      t,
    ) async {
      await pump(t);
      await openTab(t, '/quotations/q1');
      expect(await newTodoChord(t), isTrue);
      final sw = t.widget<SwitchListTile>(key('todo-link-switch'));
      expect(sw.value, isTrue);
      expect(sw.onChanged, isNotNull);
      expect(find.text('Quotation · T-q1'), findsOneWidget);
      await save(t, 'Call Peeters');
      final body = http.bodies['POST /api/v1/todo/items']! as Map;
      expect(body['title'], 'Call Peeters');
      expect(body['link_kind'], 'quotation');
      expect(body['link_id'], 'q1');
      expect(body['link_label'], 'T-q1');
      expect(body['link_location'], '/quotations/q1');
      expect(body['client_id'], isA<String>());
      expect((body['client_id'] as String).isNotEmpty, isTrue);
      expect(find.text('To-do added'), findsOneWidget);
    });

    testWidgets('the switch can turn the link off', (t) async {
      await pump(t);
      await openTab(t, '/quotations/q1');
      await newTodoChord(t);
      await t.tap(key('todo-link-switch'));
      await t.pumpAndSettle();
      await save(t, 'Plain');
      final body = http.bodies['POST /api/v1/todo/items']! as Map;
      expect(body.containsKey('link_kind'), isFalse);
      expect(body.containsKey('link_id'), isFalse);
      expect(body['client_id'], isNotNull);
    });

    testWidgets('from a list page the switch is off, disabled and explained', (
      t,
    ) async {
      await pump(t);
      expect(await newTodoChord(t), isTrue);
      final sw = t.widget<SwitchListTile>(key('todo-link-switch'));
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNull);
      expect(
        find.text('This screen has no record to link to.'),
        findsOneWidget,
      );
      await save(t, 'No link');
      final body = http.bodies['POST /api/v1/todo/items']! as Map;
      expect(body.containsKey('link_kind'), isFalse);
    });

    testWidgets('the New to-do button of the page opens the dialog', (t) async {
      await pump(t, initial: '/todo');
      expect(find.text('New to-do'), findsWidgets);
      await t.tap(key('todo-add'));
      await t.pumpAndSettle();
      // /todo is a list page: nothing to link to.
      expect(t.widget<SwitchListTile>(key('todo-link-switch')).value, isFalse);
    });

    testWidgets('the shortcut badge shows on the button while Alt is held', (
      t,
    ) async {
      await pump(t, initial: '/todo');
      expect(key('key-hint-badge'), findsNothing);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(find.text('⇧T'), findsOneWidget);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    });

    testWidgets('Shift+T does nothing without todo.use', (t) async {
      await pump(t, perms: ['orders.read', 'quotations.read']);
      expect(await newTodoChord(t), isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      await t.tap(find.byTooltip('Account'));
      await t.pumpAndSettle();
      expect(key('account-new-todo'), findsNothing);
    });

    testWidgets('with a dialog open the shortcut does not fire again', (
      t,
    ) async {
      await pump(t);
      await newTodoChord(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await newTodoChord(t), isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('the account menu offers New to-do', (t) async {
      await pump(t);
      await openTab(t, '/quotations/q1');
      await t.tap(find.byTooltip('Account'));
      await t.pumpAndSettle();
      expect(key('account-new-todo'), findsOneWidget);
      expect(find.text('Alt+Shift+T'), findsOneWidget);
      await t.tap(key('account-new-todo'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(t.widget<SwitchListTile>(key('todo-link-switch')).value, isTrue);
    });
  });

  group('the link on the to-do page', () {
    testWidgets('a readable link opens its record in a tab', (t) async {
      items = [
        _item(
          'a',
          'Call',
          linkKind: 'quotation',
          linkId: 'q9',
          linkLabel: 'Q-9',
          linkLocation: '/stale/q9',
        ),
      ];
      await pump(t, initial: '/todo');
      await t.tap(key('todo-link-a'));
      await t.pumpAndSettle();
      // Built from kind and id, not the stored location.
      expect(
        container.read(workspaceProvider).activeTab!.location,
        '/quotations/q9',
      );
      expect(find.text('detail /quotations/q9'), findsOneWidget);
    });

    testWidgets('a kind without a route uses the stored location', (t) async {
      items = [
        _item(
          'a',
          'Call',
          linkKind: 'future_kind',
          linkId: 'z1',
          linkLabel: 'Z',
          linkLocation: '/orders/z1',
        ),
      ];
      await pump(t, initial: '/todo');
      await t.tap(key('todo-link-a'));
      await t.pumpAndSettle();
      expect(
        container.read(workspaceProvider).activeTab!.location,
        '/orders/z1',
      );
    });

    testWidgets('a link the viewer may not read is not tappable', (t) async {
      items = [_item('a', 'Call', linkKind: 'quotation')];
      await pump(t, initial: '/todo');
      expect(find.text('Linked item'), findsOneWidget);
      expect(t.widget(key('todo-link-a')), isA<Chip>());
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('Remove link clears the link on the server', (t) async {
      items = [
        _item(
          'a',
          'Call',
          linkKind: 'quotation',
          linkId: 'q9',
          linkLabel: 'Q-9',
        ),
      ];
      await pump(t, initial: '/todo');
      await t.tap(key('todo-menu-a'));
      await t.pumpAndSettle();
      await t.tap(key('todo-remove-link-a'));
      await t.pumpAndSettle();
      expect(http.bodies['PATCH /api/v1/todo/items/a'], {'clear_link': true});
    });

    testWidgets('an item without a link has no Remove link entry', (t) async {
      items = [_item('a', 'Call')];
      await pump(t, initial: '/todo');
      await t.tap(key('todo-menu-a'));
      await t.pumpAndSettle();
      expect(key('todo-remove-link-a'), findsNothing);
    });
  });

  group('to-dos for this record', () {
    testWidgets('shows the count, lists the items and completes one', (
      t,
    ) async {
      items = [
        _item('a', 'Call', linkKind: 'quotation', linkId: 'q1'),
        _item('b', 'Mail', linkKind: 'quotation', linkId: 'q1'),
      ];
      await pump(t);
      await openTab(t, '/quotations/q1');
      // The list asked for this record's open items.
      final q = http.queries.lastWhere(
        (q) => q['link_id'] == 'q1',
        orElse: () => {},
      );
      expect(q['link_kind'], 'quotation');
      expect(q['done'], false);
      expect(
        t.widget<Badge>(key('object-todos-badge')).label,
        isA<Text>().having((x) => x.data, 'count', '2'),
      );
      await t.tap(key('object-todos-button'));
      await t.pumpAndSettle();
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Mail'), findsOneWidget);
      // A sheet inside a tab does not change where the tab is.
      expect(
        container.read(workspaceProvider).activeTab!.location,
        '/quotations/q1',
      );
      await t.tap(
        find.descendant(
          of: key('object-todo-a'),
          matching: find.byType(Checkbox),
        ),
      );
      await t.pumpAndSettle();
      expect(http.requests, contains('POST /api/v1/todo/items/a/complete'));
      expect(find.text('Call'), findsNothing);
      expect(find.text('Mail'), findsOneWidget);
    });

    testWidgets('adds a to-do that is already linked to the record', (t) async {
      await pump(t);
      await openTab(t, '/quotations/q1');
      await t.tap(key('object-todos-button'));
      await t.pumpAndSettle();
      expect(key('object-todos-empty'), findsOneWidget);
      await t.tap(key('object-todos-add'));
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(key('todo-link-switch')).value, isTrue);
      await save(t, 'Follow up');
      final body = http.bodies['POST /api/v1/todo/items']! as Map;
      expect(body['link_kind'], 'quotation');
      expect(body['link_id'], 'q1');
      expect(body['link_label'], 'T-q1');
      expect(body['link_location'], '/quotations/q1');
      // The sheet shows the new item.
      expect(find.text('Follow up'), findsOneWidget);
    });

    testWidgets('is hidden without todo.use', (t) async {
      await pump(t, perms: ['orders.read', 'quotations.read']);
      await openTab(t, '/quotations/q1');
      expect(key('object-todos-button'), findsNothing);
      expect(
        http.requests.where((r) => r == 'GET /api/v1/todo/items'),
        isEmpty,
      );
    });
  });

  group('customer route', () {
    testWidgets('a customer location opens the customer in a tab', (t) async {
      await pump(
        t,
        realScreens: true,
        perms: [..._perms, 'customers.write'],
        routes: {
          'GET /api/v1/customers/c2': (_) => customerJson(),
          'GET /api/v1/price-zones': (_) => [],
        },
      );
      expect(isDetailLocation('/customers/c2'), isTrue);
      ws().open('/customers/c2');
      await t.pumpAndSettle();
      expect(find.text('Bêta Industrie SA'), findsWidgets);
      expect(
        container.read(workspaceProvider).activeTab!.title,
        'Bêta Industrie SA',
      );
      expect(find.byType(AlertDialog), findsNothing);
      // The to-dos button of the customer is there.
      expect(key('object-todos-button'), findsOneWidget);
      expect(
        tabLabel(
          await AppLocalizations.delegate.load(const Locale('en')),
          const WorkTab(id: 1, location: '/customers/c2'),
        ),
        'Customer c2',
      );
    });

    testWidgets('the list keeps opening its dialog', (t) async {
      await pump(
        t,
        realScreens: true,
        initial: '/customers',
        perms: [..._perms, 'customers.write'],
        routes: {
          'GET /api/v1/customers': (_) => {
            'items': [customerJson()],
            'total': 1,
          },
          'GET /api/v1/price-zones': (_) => [],
        },
      );
      await t.tap(find.text('Bêta Industrie SA'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(container.read(workspaceProvider).tabs, isEmpty);
    });

    testWidgets('a deleted customer lands on a clear not-found state', (
      t,
    ) async {
      await pump(t, realScreens: true);
      ws().open('/customers/gone');
      await t.pumpAndSettle();
      expect(key('record-not-found'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('a link to a deleted record', () {
    Future<void> pumpScreen(WidgetTester t, Widget screen) async {
      http = FakeHttp({'GET /api/v1/me': (_) => meJson(_perms)});
      await t.pumpWidget(
        ProviderScope(
          overrides: [dioProvider.overrideWithValue(fakeDio(http))],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: screen,
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('the order screen says it was not found', (t) async {
      await pumpScreen(t, const OrderScreen(id: 'gone'));
      expect(key('record-not-found'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(key('record-back'), findsOneWidget);
    });

    testWidgets('the quotation screen says it was not found', (t) async {
      await pumpScreen(t, const QuotationScreen(id: 'gone'));
      expect(key('record-not-found'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('New quotation'), findsNothing);
    });
  });
}
