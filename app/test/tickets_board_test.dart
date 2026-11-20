import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/tickets_page.dart';
import 'package:tradocraft_app/l10n/l10n.dart';

import 'fake_http.dart';

Map<String, Object?> _ticket(
  String id,
  String status,
  String subject, {
  String priority = 'normal',
  bool unread = false,
  String? owner = 'Sales User',
  String sla = 'none',
}) => {
  'id': id,
  'version': 7,
  'number': 'T-$id',
  'subject': subject,
  'status': status,
  'priority': priority,
  'category': 'question',
  'suggested_category': null,
  'language': 'en',
  'customer_id': 'c3',
  'customer_name': 'Gamma Trading GmbH',
  'contact_name': 'Klaus Weber',
  'contact_email': 'klaus@gamma.example',
  'owner_user_id': owner == null ? null : 'u1',
  'owner_name': owner,
  'internal': false,
  'article_count': 1,
  'created_at': '2027-01-05T10:00:00Z',
  'updated_at': '2027-01-05T10:00:00Z',
  ...ticketExtras(),
  'unread': unread,
  'sla': {...(ticketExtras()['sla'] as Map<String, Object?>), 'state': sla},
};

/// A fake server that answers the ticket list by its `status`, `mine`, `unassigned` and `q`.
class _Server extends FakeHttp {
  _Server(super.routes);

  final data = <String, List<Map<String, Object?>>>{
    'new': [
      _ticket(
        '1',
        'new',
        'Water in the unit',
        priority: 'urgent',
        unread: true,
      ),
    ],
    'open': [_ticket('2', 'open', 'Filter order', owner: null)],
    'pending_customer': [],
    'pending_internal': [],
    'closed': [_ticket('3', 'closed', 'Old question')],
  };
  final listQueries = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) {
    if (o.method == 'GET' && o.path == '/api/v1/tickets') {
      listQueries.add(Map.of(o.queryParameters));
      final status = o.queryParameters['status'] as String?;
      final q = (o.queryParameters['q'] as String?)?.toLowerCase();
      final unassigned = o.queryParameters['unassigned'] == true;
      final rows = [
        for (final r in data[status] ?? const <Map<String, Object?>>[])
          if ((q == null || '${r['subject']}'.toLowerCase().contains(q)) &&
              (!unassigned || r['owner_name'] == null))
            r,
      ];
      final saved = routes['GET /api/v1/tickets'];
      routes['GET /api/v1/tickets'] = (_) => {
        'items': rows,
        'total': rows.length,
      };
      final answer = super.fetch(o, body, cancel);
      if (saved != null) routes['GET /api/v1/tickets'] = saved;
      return answer;
    }
    return super.fetch(o, body, cancel);
  }
}

Map<String, Object?> _detail(Map<String, Object?> ticket) => {
  'ticket': ticket,
  'articles': <Object?>[],
  ...detailExtras(),
};

_Server _server({
  List<String> permissions = const ['helpdesk.read', 'helpdesk.write'],
}) {
  final s = _Server({
    'GET /api/v1/me': (_) => meJson(permissions),
    'GET /api/v1/tickets': (_) => {'items': <Object?>[], 'total': 0},
    'GET /api/v1/teams': (_) => <Object?>[],
    'GET /api/v1/tags': (_) => <Object?>[],
    'GET /api/v1/tickets/1': (_) =>
        _detail(_ticket('1', 'new', 'Water in the unit')),
  });
  for (final id in ['1', '2', '3']) {
    s.routes['POST /api/v1/tickets/$id/status'] = (b) =>
        _detail(_ticket(id, (b as Map)['status'] as String, 'Moved'));
  }
  return s;
}

Future<void> _pump(WidgetTester t, _Server http) async {
  t.view.physicalSize = const Size(1700, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: TicketsPage()),
            ),
            GoRoute(
              path: '/helpdesk/:id',
              builder: (_, s) => Text('OPEN ${s.pathParameters['id']}'),
            ),
          ],
        ),
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _showBoard(WidgetTester t) async {
  await t.tap(
    find.descendant(
      of: find.byKey(const ValueKey('tickets-view')),
      matching: find.text('Board'),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _moveByMenu(WidgetTester t, String id, String to) async {
  await t.tap(find.byKey(ValueKey('kanban-menu-$id')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(ValueKey('kanban-move-$id-$to')));
  await t.pumpAndSettle();
}

Finder _card(String id) => find.byKey(ValueKey('kanban-card-$id'));
Finder _in(String status, String id) => find.descendant(
  of: find.byKey(ValueKey('kanban-column-$status')),
  matching: _card(id),
);

void main() {
  testWidgets('the list stays the default, the board is one switch away', (
    t,
  ) async {
    await _pump(t, _server());
    expect(find.byKey(const ValueKey('kanban-column-new')), findsNothing);
    await _showBoard(t);
    for (final s in ticketStatuses) {
      expect(
        find.byKey(ValueKey('kanban-column-$s')),
        findsOneWidget,
        reason: s,
      );
    }
  });

  testWidgets('every status lists its own tickets, for my tickets by default', (
    t,
  ) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    expect(_in('new', '1'), findsOneWidget);
    expect(_in('open', '2'), findsOneWidget);
    expect(_in('closed', '3'), findsOneWidget);
    final board = http.listQueries.where((q) => q['limit'] == 50).toList();
    expect(
      {for (final q in board) q['status']}.containsAll(ticketStatuses),
      isTrue,
    );
    expect(
      board.every((q) => q['mine'] == true),
      isTrue,
      reason: 'my tickets first',
    );
  });

  testWidgets(
    'a card shows what to triage by: priority, unread, customer, owner',
    (t) async {
      await _pump(t, _server());
      await _showBoard(t);
      expect(find.text('Water in the unit'), findsOneWidget);
      expect(find.text('Gamma Trading GmbH'), findsWidgets);
      expect(find.byKey(const ValueKey('ticket-priority-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-unread-1')), findsOneWidget);
      // a normal, read ticket carries neither
      expect(find.byKey(const ValueKey('ticket-priority-2')), findsNothing);
      expect(find.byKey(const ValueKey('ticket-unread-2')), findsNothing);
      expect(find.text('Sales User'), findsWidgets);
    },
  );

  testWidgets('moving a card posts the status and nothing else', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await _moveByMenu(t, '1', 'pending_customer');
    expect(
      http.bodies['POST /api/v1/tickets/1/status'],
      {'status': 'pending_customer'},
      reason:
          'no version: a colleague editing other fields must not fail the move',
    );
    expect(_in('pending_customer', '1'), findsOneWidget);
  });

  testWidgets('closing asks first, and backing out puts the card back', (
    t,
  ) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await t.tap(find.byKey(const ValueKey('kanban-menu-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kanban-move-1-closed')));
    await t.pumpAndSettle();
    expect(find.text('Close this ticket?'), findsOneWidget);
    expect(find.textContaining('T-1'), findsWidgets);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(http.requests, isNot(contains('POST /api/v1/tickets/1/status')));
    expect(_in('new', '1'), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-error')), findsNothing);
  });

  testWidgets('confirming closes the ticket', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await t.tap(find.byKey(const ValueKey('kanban-menu-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kanban-move-2-closed')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('board-close-confirm')));
    await t.pumpAndSettle();
    expect(http.bodies['POST /api/v1/tickets/2/status'], {'status': 'closed'});
    expect(_in('closed', '2'), findsOneWidget);
  });

  testWidgets('moving out of closed needs no question', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await _moveByMenu(t, '3', 'open');
    expect(find.text('Close this ticket?'), findsNothing);
    expect(http.bodies['POST /api/v1/tickets/3/status'], {'status': 'open'});
    expect(_in('open', '3'), findsOneWidget);
  });

  testWidgets(
    'a refused close (checklist) puts the card back with the server message',
    (t) async {
      final http = _server();
      http.routes['POST /api/v1/tickets/2/status'] = (_) => const FakeStatus(
        409,
        {
          'error': 'conflict',
          'code': 'checklist_incomplete',
          'message': 'Complete all checklist items before closing this ticket',
        },
      );
      await _pump(t, http);
      await _showBoard(t);
      await t.tap(find.byKey(const ValueKey('kanban-menu-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('kanban-move-2-closed')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('board-close-confirm')));
      await t.pumpAndSettle();
      expect(_in('open', '2'), findsOneWidget);
      expect(
        find.text('Complete all checklist items before closing this ticket'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the owner switch changes what every column loads', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('board-owner')),
        matching: find.text('Unassigned'),
      ),
    );
    await t.pumpAndSettle();
    expect(http.listQueries.last['unassigned'], true);
    expect(http.listQueries.last.containsKey('mine'), isFalse);
    expect(_in('open', '2'), findsOneWidget);
    expect(_card('1'), findsNothing, reason: 'owned by someone');
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('board-owner')),
        matching: find.text('All'),
      ),
    );
    await t.pumpAndSettle();
    expect(http.listQueries.last.containsKey('mine'), isFalse);
    expect(http.listQueries.last.containsKey('unassigned'), isFalse);
    expect(_card('1'), findsOneWidget);
  });

  testWidgets('searching filters every column', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await t.enterText(find.byKey(const ValueKey('board-search')), 'filter');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(http.listQueries.last['q'], 'filter');
    expect(_in('open', '2'), findsOneWidget);
    expect(_card('1'), findsNothing);
  });

  testWidgets('a card opens the ticket', (t) async {
    await _pump(t, _server());
    await _showBoard(t);
    await t.tap(find.text('Water in the unit'));
    await t.pumpAndSettle();
    expect(find.text('OPEN 1'), findsOneWidget);
  });

  testWidgets(
    '"+" is offered on every column but closed, and only with write access',
    (t) async {
      await _pump(t, _server());
      await _showBoard(t);
      for (final s in ['new', 'open', 'pending_customer', 'pending_internal']) {
        expect(
          find.byKey(ValueKey('kanban-add-$s')),
          findsOneWidget,
          reason: s,
        );
      }
      expect(find.byKey(const ValueKey('kanban-add-closed')), findsNothing);
    },
  );

  testWidgets('"+" opens the new ticket dialog; backing out changes nothing', (
    t,
  ) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    final loads = http.listQueries.length;
    await t.tap(find.byKey(const ValueKey('kanban-add-open')));
    await t.pumpAndSettle();
    expect(find.byType(NewTicketDialog), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byType(NewTicketDialog), findsNothing);
    expect(
      http.listQueries.length,
      loads,
      reason: 'no reload for a cancelled dialog',
    );
    expect(http.requests.where((r) => r.startsWith('POST')), isEmpty);
  });

  testWidgets(
    'a read-only user has no "+" and the "+" follows rights that change',
    (t) async {
      t.view.physicalSize = const Size(1700, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var permissions = ['helpdesk.read'];
      final http = _server();
      http.routes['GET /api/v1/me'] = (_) => meJson(permissions);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const Scaffold(body: TicketsPage()),
                ),
              ],
            ),
            locale: const Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await t.pumpAndSettle();
      await _showBoard(t);
      expect(find.byKey(const ValueKey('kanban-add-open')), findsNothing);
      permissions = ['helpdesk.read', 'helpdesk.write'];
      container.invalidate(meProvider);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kanban-add-open')), findsOneWidget);
      expect(_in('open', '2'), findsOneWidget, reason: 'the cards stay');
    },
  );
}
