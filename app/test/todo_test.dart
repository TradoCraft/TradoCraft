import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/todo/todo_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _item(
  String id,
  String title, {
  String? parent,
  bool done = false,
  String? due,
  String? linkKind,
  String? linkLabel,
  bool mine = true,
  bool unreadableLink = false,
}) => {
  'id': id,
  'parent_id': parent,
  'position': 0,
  'title': title,
  'notes': '',
  'owner_id': mine ? 'u1' : 'u2',
  'owner_name': mine ? 'Me' : 'Colleague',
  'assignee_id': null,
  'assignee_name': null,
  'created_by': 'u1',
  'mine': mine,
  'due_date': due,
  'done': done,
  'done_at': null,
  'done_by': null,
  'link_kind': linkKind,
  // The server omits the id of a link the viewer may not read.
  'link_id': linkKind == null || unreadableLink ? null : 'q1',
  'link_label': linkLabel,
  'link_location': null,
  'client_id': null,
  'created_at': '2027-02-02T09:00:00Z',
  'updated_at': '2027-02-02T09:00:00Z',
};

/// A fake server with a list the test can change; every call is recorded in the returned http.
class _Server {
  _Server(this.items);

  final List<Map<String, Object?>> items;
  late final FakeHttp http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(['todo.use']),
    'GET /api/v1/todo/items': (_) => items,
    'GET /api/v1/todo/settings': (_) => {'email_reminders': true},
    'POST /api/v1/todo/items': (b) {
      final body = b as Map;
      final item = _item(
        'new${items.length}',
        body['title'] as String,
        parent: body['parent_id'] as String?,
      );
      items.add(item);
      return FakeStatus(201, item);
    },
    'POST /api/v1/todo/items/reorder': (_) => null,
    'POST /api/v1/todo/items/p/complete': (_) {
      for (final i in items) {
        i['done'] = true;
      }
      return items.first;
    },
    'POST /api/v1/todo/items/a/complete': (_) => items.first,
    'POST /api/v1/todo/items/c1/complete': (_) => items.last,
    'POST /api/v1/todo/items/a/reopen': (_) => items.first,
    'DELETE /api/v1/todo/items/a': (_) => null,
  });
}

Future<void> _pump(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(server.http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TodoPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Query of the latest list request (the page also asks for its settings).
Map<String, dynamic> _lastList(FakeHttp http) =>
    http.queries[http.requests.lastIndexOf('GET /api/v1/todo/items')];

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  test(
    'the tree puts sub-items under their root and keeps orphans as roots',
    () {
      final items = [
        TodoItem.fromJson(_item('a', 'A')),
        TodoItem.fromJson(_item('b', 'B')),
        TodoItem.fromJson(_item('a1', 'A1', parent: 'a')),
        TodoItem.fromJson(_item('z1', 'Z1', parent: 'gone', done: true)),
      ];
      final tree = buildTodoTree(items);
      expect(tree.map((n) => n.item.id), ['a', 'b', 'z1']);
      expect(tree.first.children.map((c) => c.id), ['a1']);
      expect(tree.first.hasOpenChildren, true);
    },
  );

  testWidgets('an empty list says so and offers to add the first item', (
    tester,
  ) async {
    await _pump(tester, _Server([]));
    expect(_key('todo-empty'), findsOneWidget);
    expect(find.text('Nothing to do. Add your first to-do.'), findsOneWidget);
    expect(_key('todo-add'), findsOneWidget);
  });

  testWidgets('the filter asks the server for open, done or all items', (
    tester,
  ) async {
    final server = _Server([]);
    await _pump(tester, server);
    expect(_lastList(server.http)['done'], false);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(_lastList(server.http)['done'], true);
    expect(find.text('No finished to-dos.'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(_lastList(server.http).containsKey('done'), false);
  });

  testWidgets('adding an item sends it with a client id and lists it', (
    tester,
  ) async {
    final server = _Server([]);
    await _pump(tester, server);
    await tester.tap(_key('todo-add'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('todo-title-field'), 'Call Peeters');
    await tester.tap(_key('todo-dialog-save'));
    await tester.pumpAndSettle();
    final sent = server.http.bodies['POST /api/v1/todo/items'] as Map;
    expect(sent['title'], 'Call Peeters');
    expect(sent['parent_id'], isNull);
    expect(sent['client_id'], isA<String>());
    expect(find.text('Call Peeters'), findsOneWidget);
    expect(_key('todo-empty'), findsNothing);
  });

  testWidgets('a blank title is not sent', (tester) async {
    final server = _Server([]);
    await _pump(tester, server);
    await tester.tap(_key('todo-add'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('todo-title-field'), '   ');
    await tester.tap(_key('todo-dialog-save'));
    await tester.pumpAndSettle();
    expect(server.http.requests, isNot(contains('POST /api/v1/todo/items')));
  });

  testWidgets('a sub-item is added under its parent', (tester) async {
    final server = _Server([_item('a', 'Prepare visit')]);
    await _pump(tester, server);
    await tester.tap(_key('todo-menu-a'));
    await tester.pumpAndSettle();
    await tester.tap(_key('todo-add-sub-a'));
    await tester.pumpAndSettle();
    expect(find.text('Add sub-item'), findsWidgets);
    await tester.enterText(_key('todo-title-field'), 'Pack tools');
    await tester.tap(_key('todo-dialog-save'));
    await tester.pumpAndSettle();
    final sent = server.http.bodies['POST /api/v1/todo/items'] as Map;
    expect(sent['parent_id'], 'a');
    expect(sent['title'], 'Pack tools');
    expect(find.text('Pack tools'), findsOneWidget);
    expect(find.text('0 of 1 sub-items done'), findsOneWidget);
  });

  testWidgets('completing a leaf needs no confirmation', (tester) async {
    final server = _Server([_item('a', 'Alone')]);
    await _pump(tester, server);
    await tester.tap(_key('todo-check-a'));
    await tester.pumpAndSettle();
    expect(find.text('Complete the sub-items too?'), findsNothing);
    final sent =
        server.http.bodies['POST /api/v1/todo/items/a/complete'] as Map;
    expect(sent['complete_children'], false);
  });

  testWidgets('completing a parent with open sub-items asks first', (
    tester,
  ) async {
    final server = _Server([
      _item('p', 'Parent'),
      _item('c1', 'Child', parent: 'p'),
    ]);
    await _pump(tester, server);
    // Cancelling changes nothing.
    await tester.tap(_key('todo-check-p'));
    await tester.pumpAndSettle();
    expect(find.text('Complete the sub-items too?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      server.http.requests,
      isNot(contains('POST /api/v1/todo/items/p/complete')),
    );
    // Confirming completes the parent with its sub-items.
    await tester.tap(_key('todo-check-p'));
    await tester.pumpAndSettle();
    await tester.tap(_key('todo-complete-all'));
    await tester.pumpAndSettle();
    final sent =
        server.http.bodies['POST /api/v1/todo/items/p/complete'] as Map;
    expect(sent['complete_children'], true);
  });

  testWidgets('the server refusing an open sub-item the list hides asks too', (
    tester,
  ) async {
    var calls = 0;
    final server = _Server([_item('a', 'Alone')]);
    server.http.routes['POST /api/v1/todo/items/a/complete'] = (b) {
      calls++;
      return (b as Map)['complete_children'] == true
          ? server.items.first
          : const FakeStatus(409, {
              'error': 'conflict',
              'code': 'open_sub_items',
              'message': '1 sub-item(s) are still open',
            });
    };
    await _pump(tester, server);
    await tester.tap(_key('todo-check-a'));
    await tester.pumpAndSettle();
    expect(find.text('Complete the sub-items too?'), findsOneWidget);
    await tester.tap(_key('todo-complete-all'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('a finished item is reopened with its checkbox', (tester) async {
    final server = _Server([_item('a', 'Done thing', done: true)]);
    await _pump(tester, server);
    await tester.tap(_key('todo-check-a'));
    await tester.pumpAndSettle();
    expect(server.http.requests, contains('POST /api/v1/todo/items/a/reopen'));
  });

  testWidgets('deleting asks, then deletes', (tester) async {
    final server = _Server([_item('a', 'Obsolete')]);
    await _pump(tester, server);
    await tester.tap(_key('todo-menu-a'));
    await tester.pumpAndSettle();
    await tester.tap(_key('todo-delete-a'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Obsolete'), findsWidgets);
    await tester.tap(_key('todo-confirm-delete'));
    await tester.pumpAndSettle();
    expect(server.http.requests, contains('DELETE /api/v1/todo/items/a'));
  });

  testWidgets('only the owner is offered to delete an item', (tester) async {
    final server = _Server([_item('a', 'Handed to me', mine: false)]);
    await _pump(tester, server);
    expect(find.text('From Colleague'), findsOneWidget);
    await tester.tap(_key('todo-menu-a'));
    await tester.pumpAndSettle();
    expect(_key('todo-delete-a'), findsNothing);
  });

  testWidgets('dragging an item sends the new order of its siblings', (
    tester,
  ) async {
    final server = _Server([_item('a', 'First'), _item('b', 'Second')]);
    await _pump(tester, server);
    await tester.timedDrag(
      find.byIcon(Icons.drag_handle).first,
      const Offset(0, 120),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    final sent = server.http.bodies['POST /api/v1/todo/items/reorder'] as Map;
    expect(sent['parent_id'], isNull);
    expect(sent['ids'], ['b', 'a']);
  });

  testWidgets(
    'a sub-item shown as a root has no sub-item entry and no handle',
    (tester) async {
      final server = _Server([
        _item('c1', 'Orphan', parent: 'gone', done: true),
      ]);
      await _pump(tester, server);
      expect(find.text('Orphan'), findsOneWidget);
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      await tester.tap(_key('todo-menu-c1'));
      await tester.pumpAndSettle();
      expect(_key('todo-add-sub-c1'), findsNothing);
    },
  );

  testWidgets('due dates and the link chip show; a hidden label says so', (
    tester,
  ) async {
    final server = _Server([
      _item(
        'a',
        'Follow up',
        due: '2020-01-31',
        linkKind: 'quotation',
        linkLabel: 'Q-2027-001',
      ),
      _item('b', 'Other', linkKind: 'quotation', unreadableLink: true),
    ]);
    await _pump(tester, server);
    expect(find.textContaining('Overdue'), findsOneWidget);
    expect(find.textContaining('31/01/2020'), findsOneWidget);
    expect(find.text('Q-2027-001'), findsOneWidget);
    expect(find.text('Linked item'), findsOneWidget);
    // Only the readable link can be tapped (the jump itself is tested in todo_context_test).
    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Q-2027-001'), findsOneWidget);
  });

  group('navigation', () {
    Future<void> shell(WidgetTester tester, List<String> perms) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(perms),
        'GET /api/v1/todo/items': (_) => [],
        'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
      });
      final router = GoRouter(
        initialLocation: '/quotations',
        routes: [
          ShellRoute(
            builder: (c, s, child) =>
                AppShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(path: '/todo', builder: (_, _) => const TodoPage()),
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
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the To-dos destination needs todo.use', (tester) async {
      await shell(tester, ['todo.use', 'quotations.read']);
      expect(find.text('To-dos'), findsOneWidget);
    });

    testWidgets('without todo.use there is no entry', (tester) async {
      await shell(tester, ['quotations.read']);
      expect(find.text('To-dos'), findsNothing);
    });
  });
}
