import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_screen.dart';
import 'package:tradocraft_app/features/helpdesk/tickets_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

const _perms = ['helpdesk.read', 'helpdesk.write', 'helpdesk.reply'];

Map<String, Object?> _ticket({
  String id = 't1',
  String number = 'T2026-00007',
  String subject = 'Pump is noisy',
  bool unread = false,
  bool escalated = false,
  String priority = 'normal',
}) => {
  'id': id,
  'number': number,
  'subject': subject,
  'status': 'open',
  'priority': priority,
  'category': 'service',
  'language': 'en',
  'customer_id': 'c1',
  'customer_name': 'Alpha NV',
  'contact_name': 'Anna',
  'contact_email': 'anna@alpha.example',
  'owner_user_id': 'u1',
  'owner_name': 'Support Agent',
  'internal': false,
  'article_count': 1,
  'created_at': '2026-11-09T09:00:00Z',
  'updated_at': '2026-11-09T09:00:00Z',
  ...ticketExtras(),
  'unread': unread,
  'escalated_at': escalated ? '2026-11-09T10:00:00Z' : null,
  'escalated_by': escalated ? 'u1' : null,
  'escalated_by_name': escalated ? 'Support Agent' : null,
};

Map<String, Object?> _detail({
  bool escalated = false,
  String priority = 'normal',
  List<Map<String, Object?>> watchers = const [],
  List<Map<String, Object?>> readers = const [],
}) => {
  'ticket': _ticket(escalated: escalated, priority: priority),
  'articles': [
    {
      'id': 'a1',
      'kind': 'email_in',
      'from_address': 'anna@alpha.example',
      'from_name': 'Anna',
      'to_addresses': ['sales@example.com'],
      'cc_addresses': <String>[],
      'subject': 'Pump',
      'body': 'It is loud.',
      'attachments': <Object?>[],
      'created_at': '2026-11-09T09:00:00Z',
    },
  ],
  'watchers': watchers,
  'readers': readers,
};

Map<String, Object?> _watcher(String id, String name) => {
  'user_id': id,
  'user_name': name,
  'created_at': '2026-11-09T09:00:00Z',
};

Map<String, Object?> _user(String id, String name) => {
  'id': id,
  'display_name': name,
  'email': '$id@example.com',
  'roles': ['support'],
};

Map<String, Object?> _presence(String mode) => {
  'user_id': 'u2',
  'user_name': 'Jo',
  'mode': mode,
  'seen_at': '2026-11-09T11:00:00Z',
};

Map<String, Object?> _event(
  String id,
  String kind,
  int minute, {
  String source = 'event',
  String? actor = 'Support Agent',
  String comment = '',
}) => {
  'id': id,
  'source': source,
  'kind': kind,
  'at': '2026-11-09T10:${minute.toString().padLeft(2, '0')}:00Z',
  'actor_name': actor,
  'comment': comment,
};

FakeHttp _http({
  List<String> perms = _perms,
  Map<String, Object? Function(Object?)> extra = const {},
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/users': (_) => [_user('u1', 'Support Agent'), _user('u2', 'Jo')],
  'GET /api/v1/helpdesk/teams': (_) => [
    {
      'id': 'team1',
      'name': 'Level 2',
      'active': true,
      'members': <Object?>[],
      'created_at': '2026-11-01T09:00:00Z',
    },
  ],
  'GET /api/v1/tickets/t1': (_) => _detail(
    watchers: [_watcher('u2', 'Jo')],
    readers: [
      {
        'user_id': 'u2',
        'user_name': 'Jo',
        'last_read_at': '2026-11-09T12:02:00Z',
      },
    ],
  ),
  'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
  'GET /api/v1/opportunities': (_) => {'items': [], 'total': 0},
  'GET /api/v1/customers/c1/contacts': (_) => [],
  'GET /api/v1/tickets/t1/repairs': (_) => [],
  'GET /api/v1/tickets/t1/time-entries': (_) => {
    'items': <Object?>[],
    'total_minutes': 0,
    'billable_minutes': 0,
  },
  'GET /api/v1/tickets/t1/events': (_) => [
    _event('e1', 'created', 0),
    _event('e2', 'email_in', 1, source: 'message', actor: 'Anna'),
    _event('e3', 'escalated', 2, comment: 'Customer is waiting'),
  ],
  'POST /api/v1/tickets/t1/read': (_) => null,
  'POST /api/v1/tickets/t1/presence': (_) => <Object?>[],
  'GET /api/v1/tickets/t1/presence': (_) => <Object?>[],
  ...extra,
});

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Removes the screen so its heartbeat timer is cancelled.
Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

Finder _targetPicker() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(DropdownButtonFormField<String?>),
);

Future<void> _pick(WidgetTester tester, String text) async {
  await tester.tap(_targetPicker());
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('escalating needs a reason and sends target and priority', (
    tester,
  ) async {
    final http = _http(
      extra: {
        'POST /api/v1/tickets/t1/escalate': (_) =>
            _detail(escalated: true, priority: 'high'),
      },
    );
    await _pump(tester, http, const TicketScreen(id: 't1'));
    expect(find.byKey(const ValueKey('escalated-badge')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('escalate-ticket')));
    await tester.tap(find.byKey(const ValueKey('escalate-ticket')));
    await tester.pumpAndSettle();
    FilledButton submit() =>
        tester.widget(find.byKey(const ValueKey('collab-submit')));
    expect(submit().onPressed, isNull, reason: 'a reason is required');

    await _pick(tester, 'Colleague: Jo');
    await tester.enterText(
      find.byKey(const ValueKey('collab-text')),
      'Customer is waiting',
    );
    await tester.tap(find.byKey(const ValueKey('collab-raise')));
    await tester.pump();
    expect(submit().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('collab-submit')));
    await tester.pumpAndSettle();

    expect(http.bodies['POST /api/v1/tickets/t1/escalate'], {
      'reason': 'Customer is waiting',
      'to_user_id': 'u2',
      'raise_priority': true,
    });
    expect(find.text('Ticket escalated'), findsOneWidget);
    expect(find.byKey(const ValueKey('escalated-badge')), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('escalating to a team sends the team and no user', (
    tester,
  ) async {
    final http = _http(
      extra: {
        'POST /api/v1/tickets/t1/escalate': (_) => _detail(escalated: true),
      },
    );
    await _pump(tester, http, const TicketScreen(id: 't1'));
    await tester.ensureVisible(find.byKey(const ValueKey('escalate-ticket')));
    await tester.tap(find.byKey(const ValueKey('escalate-ticket')));
    await tester.pumpAndSettle();
    await _pick(tester, 'Team: Level 2');
    await tester.enterText(find.byKey(const ValueKey('collab-text')), 'Why');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('collab-submit')));
    await tester.pumpAndSettle();
    expect(http.bodies['POST /api/v1/tickets/t1/escalate'], {
      'reason': 'Why',
      'to_team_id': 'team1',
      'raise_priority': false,
    });
    await _leave(tester);
  });

  testWidgets('handing over sends the new owner and the internal comment', (
    tester,
  ) async {
    final http = _http(
      extra: {'POST /api/v1/tickets/t1/delegate': (_) => _detail()},
    );
    await _pump(tester, http, const TicketScreen(id: 't1'));
    await tester.ensureVisible(find.byKey(const ValueKey('delegate-ticket')));
    await tester.tap(find.byKey(const ValueKey('delegate-ticket')));
    await tester.pumpAndSettle();
    expect(find.text('Internal: never sent to the customer.'), findsOneWidget);
    FilledButton submit() =>
        tester.widget(find.byKey(const ValueKey('collab-submit')));
    expect(submit().onPressed, isNull, reason: 'a new owner is required');
    // The current owner is not offered.
    await tester.tap(_targetPicker());
    await tester.pumpAndSettle();
    expect(find.text('Colleague: Support Agent'), findsNothing);
    await tester.tap(find.text('Colleague: Jo').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('collab-text')),
      'Please call him back',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('collab-submit')));
    await tester.pumpAndSettle();
    expect(http.bodies['POST /api/v1/tickets/t1/delegate'], {
      'to_user_id': 'u2',
      'comment': 'Please call him back',
    });
    expect(find.text('Ticket handed over'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('escalate and hand over are for helpdesk writers only', (
    tester,
  ) async {
    final http = _http(perms: ['helpdesk.read']);
    await _pump(tester, http, const TicketScreen(id: 't1'));
    expect(find.byKey(const ValueKey('escalate-ticket')), findsNothing);
    expect(find.byKey(const ValueKey('delegate-ticket')), findsNothing);
    expect(find.byKey(const ValueKey('watcher-add')), findsNothing);
    // Reading and following are still possible.
    expect(find.byKey(const ValueKey('watch-toggle')), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('the ticket is marked read, shows who read it and the activity', (
    tester,
  ) async {
    final http = _http();
    await _pump(tester, http, const TicketScreen(id: 't1'));
    expect(http.requests, contains('POST /api/v1/tickets/t1/read'));
    expect(find.byKey(const ValueKey('seen-by')), findsOneWidget);
    expect(find.textContaining('Seen by Jo '), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('activity-e1')));
    expect(find.text('Support Agent created the ticket'), findsOneWidget);
    expect(find.text('Anna (customer) wrote'), findsOneWidget);
    expect(find.text('Support Agent escalated the ticket'), findsOneWidget);
    expect(find.text('Customer is waiting'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('watch and stop watching, with the watchers as chips', (
    tester,
  ) async {
    final http = _http(
      extra: {
        'PUT /api/v1/tickets/t1/watch': (_) => [
          _watcher('u1', 'Support Agent'),
          _watcher('u2', 'Jo'),
        ],
        'DELETE /api/v1/tickets/t1/watch': (_) => [_watcher('u2', 'Jo')],
        'POST /api/v1/tickets/t1/watchers': (_) => [
          _watcher('u1', 'Support Agent'),
          _watcher('u2', 'Jo'),
        ],
      },
    );
    await _pump(tester, http, const TicketScreen(id: 't1'));
    expect(find.byKey(const ValueKey('watcher-u2')), findsOneWidget);
    expect(find.byKey(const ValueKey('watcher-u1')), findsNothing);
    expect(find.text('Watch'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('watch-toggle')));
    await tester.tap(find.byKey(const ValueKey('watch-toggle')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('PUT /api/v1/tickets/t1/watch'));
    expect(find.byKey(const ValueKey('watcher-u1')), findsOneWidget);
    expect(find.text('Stop watching'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('watch-toggle')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('DELETE /api/v1/tickets/t1/watch'));
    expect(find.byKey(const ValueKey('watcher-u1')), findsNothing);
    expect(find.text('Watch'), findsOneWidget);

    // Adding a colleague.
    await tester.tap(find.byKey(const ValueKey('watcher-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('watcher-option-u1')));
    await tester.pumpAndSettle();
    expect(http.bodies['POST /api/v1/tickets/t1/watchers'], {'user_id': 'u1'});
    await _leave(tester);
  });

  testWidgets('the ticket list marks unread and escalated tickets', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(_perms),
      'GET /api/v1/helpdesk/teams': (_) => [],
      'GET /api/v1/helpdesk/tags': (_) => [],
      'GET /api/v1/tickets': (_) => {
        'items': [
          _ticket(unread: true, escalated: true),
          _ticket(id: 't2', number: 'T2026-00008', subject: 'Calm one'),
        ],
        'total': 2,
      },
    });
    await _pump(tester, http, const Scaffold(body: TicketsPage()));
    expect(find.byKey(const ValueKey('unread-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-t2')), findsNothing);
    expect(find.byKey(const ValueKey('escalated-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('escalated-t2')), findsNothing);
    final bold = tester.widget<Text>(find.text('Pump is noisy'));
    expect(bold.style?.fontWeight, FontWeight.bold);
    final plain = tester.widget<Text>(find.text('Calm one'));
    expect(plain.style?.fontWeight, FontWeight.normal);

    // Filters: each sends its own flag and they combine.
    expect(http.queries.last['unread'], isNull);
    await tester.tap(find.byKey(const ValueKey('filter-unread')));
    await tester.pumpAndSettle();
    expect(http.queries.last['unread'], true);
    await tester.tap(find.byKey(const ValueKey('filter-watching')));
    await tester.pumpAndSettle();
    expect(http.queries.last['watching'], true);
    expect(http.queries.last['unread'], true);
    await tester.tap(find.byKey(const ValueKey('filter-escalated')));
    await tester.pumpAndSettle();
    expect(http.queries.last['escalated'], true);
    await tester.tap(find.byKey(const ValueKey('filter-unread')));
    await tester.pumpAndSettle();
    expect(http.queries.last['unread'], isNull);
    expect(http.queries.last['escalated'], true);
  });

  testWidgets(
    'a colleague who is replying shows a banner and asks before sending',
    (tester) async {
      final http = _http(
        extra: {
          'POST /api/v1/tickets/t1/presence': (_) => [_presence('replying')],
          'GET /api/v1/tickets/t1/presence': (_) => [_presence('replying')],
          'POST /api/v1/tickets/t1/replies': (_) => _detail(),
        },
      );
      await _pump(tester, http, const TicketScreen(id: 't1'));
      expect(find.byKey(const ValueKey('presence-banner')), findsOneWidget);
      expect(
        find.text('Jo is replying — coordinate before sending'),
        findsOneWidget,
      );

      // Sending asks first; cancelling sends nothing.
      await tester.enterText(
        find.widgetWithText(TextField, 'Message'),
        'Dear Anna',
      );
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(
        find.text('Jo is replying to this ticket right now. Send anyway?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(http.requests, isNot(contains('POST /api/v1/tickets/t1/replies')));

      // Send anyway.
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('send-anyway')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('POST /api/v1/tickets/t1/replies'));
      await _leave(tester);
    },
  );

  testWidgets('without colleagues replying, sending needs no confirmation', (
    tester,
  ) async {
    final http = _http(
      extra: {
        'POST /api/v1/tickets/t1/presence': (_) => [_presence('viewing')],
        'GET /api/v1/tickets/t1/presence': (_) => [_presence('viewing')],
        'POST /api/v1/tickets/t1/replies': (_) => _detail(),
      },
    );
    await _pump(tester, http, const TicketScreen(id: 't1'));
    expect(find.text('Jo is viewing this ticket'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Message'),
      'Dear Anna',
    );
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-anyway')), findsNothing);
    expect(http.requests, contains('POST /api/v1/tickets/t1/replies'));
    await _leave(tester);
  });

  testWidgets(
    'the screen sends a heartbeat that switches to replying when typing',
    (tester) async {
      final http = _http();
      await _pump(tester, http, const TicketScreen(id: 't1'));
      const beat = 'POST /api/v1/tickets/t1/presence';
      int beats() => http.requests.where((r) => r == beat).length;
      expect(beats(), 1);
      expect(http.bodies[beat], {'mode': 'viewing'});

      await tester.pump(const Duration(seconds: 20));
      expect(beats(), 2, reason: 'a beat every 20 seconds');
      await tester.pump(const Duration(seconds: 20));
      expect(beats(), 3);

      // Typing in the reply box announces "replying" at once.
      await tester.enterText(
        find.widgetWithText(TextField, 'Message'),
        'Dear Anna',
      );
      await tester.pump();
      expect(beats(), 4);
      expect(http.bodies[beat], {'mode': 'replying'});

      await _leave(tester);
      await tester.pump(const Duration(seconds: 60));
      expect(beats(), 4, reason: 'no beats after the screen was closed');
    },
  );

  testWidgets('the heartbeat pauses while the ticket tab is not focused', (
    tester,
  ) async {
    final http = _http();
    final focused = ValueNotifier(true);
    addTearDown(focused.dispose);
    await _pump(
      tester,
      http,
      ValueListenableBuilder<bool>(
        valueListenable: focused,
        builder: (_, active, _) => TabScope(
          id: 1,
          active: active,
          dirty: ValueNotifier(false),
          setTitle: (_) {},
          child: const TicketScreen(id: 't1'),
        ),
      ),
    );
    const beat = 'POST /api/v1/tickets/t1/presence';
    int beats() => http.requests.where((r) => r == beat).length;
    expect(beats(), 1);

    focused.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 60));
    expect(beats(), 1, reason: 'no beats from a background tab');

    focused.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(beats(), 2, reason: 'a beat at once when the tab is focused again');
    await tester.pump(const Duration(seconds: 20));
    expect(beats(), 3);
    await _leave(tester);
  });
}
