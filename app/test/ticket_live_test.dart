import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_merge.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

// ---------------------------------------------------------------------------------------------
// The merge rule (pure)
// ---------------------------------------------------------------------------------------------

TicketValues _v({
  String subject = 'Pump',
  String priority = 'normal',
  String? owner = 'u1',
}) => {
  for (final f in TicketField.values) f: null,
  TicketField.subject: subject,
  TicketField.status: 'open',
  TicketField.priority: priority,
  TicketField.owner: owner,
};

void _mergeTests() {
  group('mergeTicketFields', () {
    test('a colleague\'s change to a field I did not touch is taken over', () {
      final m = mergeTicketFields(
        base: _v(),
        mine: _v(subject: 'Pump noisy'),
        theirs: _v(priority: 'high'),
      );
      expect(m.conflicts, isEmpty);
      expect(m.takenFromTheirs, [TicketField.priority]);
      expect(m.resolved[TicketField.priority], 'high');
      expect(m.resolved[TicketField.subject], 'Pump noisy');
    });

    test('the same change by both is no conflict', () {
      final m = mergeTicketFields(
        base: _v(),
        mine: _v(priority: 'high'),
        theirs: _v(priority: 'high'),
      );
      expect(m.conflicts, isEmpty);
      expect(m.takenFromTheirs, isEmpty);
      expect(m.resolved[TicketField.priority], 'high');
    });

    test('different changes to one field are a conflict, mine by default', () {
      final m = mergeTicketFields(
        base: _v(),
        mine: _v(subject: 'Mine'),
        theirs: _v(subject: 'Theirs'),
      );
      expect(m.conflicts, [TicketField.subject]);
      expect(m.resolved[TicketField.subject], 'Mine');
    });

    test('an empty text and no value are the same', () {
      expect(sameValue(null, ''), isTrue);
      expect(sameValue('a', null), isFalse);
      final m = mergeTicketFields(
        base: _v(owner: null),
        mine: _v(owner: ''),
        theirs: _v(owner: 'u2'),
      );
      expect(m.takenFromTheirs, [TicketField.owner]);
      expect(m.resolved[TicketField.owner], 'u2');
    });
  });
}

// ---------------------------------------------------------------------------------------------
// The open ticket screen
// ---------------------------------------------------------------------------------------------

/// The fake server, plus a live event stream that the test feeds.
class _LiveHttp implements HttpClientAdapter {
  _LiveHttp(this.inner);
  final FakeHttp inner;
  final events = StreamController<Uint8List>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) {
    if (o.path.endsWith('/events/records')) {
      return Future.value(ResponseBody(events.stream, 200));
    }
    return inner.fetch(o, body, cancel);
  }

  /// A `record_changed` frame from the colleague Jo (the signed-in user is u1).
  void push(String kind, {int version = 3}) => events.add(
    Uint8List.fromList(
      utf8.encode(
        'event: record_changed\ndata: ${jsonEncode({'entity_type': 'ticket', 'record_id': 't1', 'version': version, 'changed_by_id': 'u2', 'changed_by_name': 'Jo', 'kind': kind, 'summary': null, 'at': '2026-11-09T11:00:00Z'})}\n\n',
      ),
    ),
  );

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _detail({
  String subject = 'Pump is noisy',
  String priority = 'normal',
  int version = 2,
  List<String> messages = const ['It is loud.'],
}) => {
  'ticket': {
    'id': 't1',
    'number': 'T2026-00007',
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
    'article_count': messages.length,
    'created_at': '2026-11-09T09:00:00Z',
    'updated_at': '2026-11-09T09:00:00Z',
    'version': version,
    ...ticketExtras(),
  },
  'articles': [
    for (var i = 0; i < messages.length; i++)
      {
        'id': 'a$i',
        'kind': 'email_in',
        'from_address': 'anna@alpha.example',
        'from_name': 'Anna',
        'to_addresses': ['sales@example.com'],
        'cc_addresses': <String>[],
        'subject': 'Pump',
        'body': messages[i],
        'attachments': <Object?>[],
        'created_at': '2026-11-09T09:0$i:00Z',
      },
  ],
  'watchers': <Object?>[],
  'readers': <Object?>[],
};

Map<String, Object?> _presence() => {
  'user_id': 'u2',
  'user_name': 'Jo',
  'mode': 'viewing',
  'seen_at': '2026-11-09T11:00:00Z',
};

class _Screen {
  _Screen(this.http, this.live);
  final FakeHttp http;
  final _LiveHttp live;

  /// What `GET /tickets/t1` answers; tests change it before pushing an event.
  Map<String, Object?> detail = _detail();
  List<Object?> presence = [];

  int calls(String key) => http.requests.where((r) => r == key).length;
}

Future<_Screen> _open(WidgetTester tester) async {
  late _Screen screen;
  final http = FakeHttp({
    'GET /api/v1/me': (_) =>
        meJson(['helpdesk.read', 'helpdesk.write', 'helpdesk.reply']),
    'GET /api/v1/users': (_) => [
      {
        'id': 'u1',
        'display_name': 'Support Agent',
        'email': 'u1@example.com',
        'roles': ['support'],
      },
    ],
    'GET /api/v1/helpdesk/teams': (_) => <Object?>[],
    'GET /api/v1/tickets/t1': (_) => screen.detail,
    'PUT /api/v1/tickets/t1': (_) => screen.detail,
    'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
    'GET /api/v1/opportunities': (_) => {'items': [], 'total': 0},
    'GET /api/v1/customers/c1/contacts': (_) => [],
    'GET /api/v1/tickets/t1/repairs': (_) => [],
    'GET /api/v1/tickets/t1/time-entries': (_) => {
      'items': <Object?>[],
      'total_minutes': 0,
      'billable_minutes': 0,
    },
    'GET /api/v1/tickets/t1/events': (_) => <Object?>[],
    'POST /api/v1/tickets/t1/read': (_) => null,
    'POST /api/v1/tickets/t1/presence': (_) => <Object?>[],
    'GET /api/v1/tickets/t1/presence': (_) => screen.presence,
  });
  final live = _LiveHttp(http);
  screen = _Screen(http, live);
  addTearDown(live.events.close);
  tester.view.physicalSize = const Size(1700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = live,
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TicketScreen(id: 't1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return screen;
}

/// Lets a pushed event travel through the stream, the refresh request and the rebuild.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

Finder _subjectField() => find.byWidgetPredicate(
  (w) =>
      w is EditableText &&
      (w.controller.text == 'Pump is noisy' ||
          w.controller.text.startsWith('Pump is') ||
          w.controller.text == 'Mine' ||
          w.controller.text == 'Theirs'),
);

Future<void> _leave(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  _mergeTests();

  testWidgets('a colleague\'s message appears at once and is announced', (
    tester,
  ) async {
    final s = await _open(tester);
    expect(find.text('It is loud.'), findsOneWidget);

    s.detail = _detail(version: 3, messages: ['It is loud.', 'Jo asked Anna.']);
    s.live.push('note');
    await _settle(tester);

    expect(find.text('Jo asked Anna.'), findsOneWidget);
    expect(find.text('Jo added a message.'), findsOneWidget);
    expect(find.text('Compare'), findsNothing);
    await _leave(tester);
  });

  testWidgets(
    'a change that does not move the version still reaches the screen',
    (tester) async {
      final s = await _open(tester);
      final timeCalls = s.calls('GET /api/v1/tickets/t1/time-entries');
      final activityCalls = s.calls('GET /api/v1/tickets/t1/events');
      // A tag or a time entry leaves the ticket version as it was.
      s.detail = _detail(messages: ['It is loud.', 'Time logged.']);
      s.live.push('time', version: 2);
      await _settle(tester);

      // The panels that load themselves load again.
      expect(s.calls('GET /api/v1/tickets/t1/time-entries'), timeCalls + 1);
      expect(s.calls('GET /api/v1/tickets/t1/events'), activityCalls + 1);
      expect(find.text('Time logged.'), findsOneWidget);
      expect(find.text('Jo logged time.'), findsOneWidget);
      await _leave(tester);
    },
  );

  testWidgets('presence arrives without waiting for the next beat', (
    tester,
  ) async {
    final s = await _open(tester);
    final before = s.calls('GET /api/v1/tickets/t1/presence');
    s.presence = [_presence()];
    s.live.push('presence', version: 2);
    await _settle(tester);

    expect(s.calls('GET /api/v1/tickets/t1/presence'), before + 1);
    expect(find.byKey(const ValueKey('presence-banner')), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('edits survive a colleague\'s change to another field', (
    tester,
  ) async {
    final s = await _open(tester);
    await tester.enterText(_subjectField(), 'Mine');
    await tester.pump();

    s.detail = _detail(priority: 'high', version: 3);
    s.live.push('updated');
    await _settle(tester);

    expect(find.text('Compare'), findsNothing);
    expect(
      find.text(
        'Jo changed this ticket. Their changes were merged into your form.',
      ),
      findsOneWidget,
    );
    final field = tester.widget<EditableText>(_subjectField());
    expect(field.controller.text, 'Mine');

    // Saving now goes out from the colleague's version and carries both changes.
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final sent = s.http.bodies['PUT /api/v1/tickets/t1'] as Map;
    expect(sent['expected_version'], 3);
    expect(sent['priority'], 'high');
    expect(sent['subject'], 'Mine');
    await _leave(tester);
  });

  testWidgets(
    'a field both people changed is compared, and the choice applies',
    (tester) async {
      final s = await _open(tester);
      await tester.enterText(_subjectField(), 'Mine');
      await tester.pump();

      s.detail = _detail(subject: 'Theirs', version: 3);
      s.live.push('updated');
      await _settle(tester);

      expect(
        find.text(
          'Jo changed this ticket while you have unsaved edits. Compare before you save.',
        ),
        findsOneWidget,
      );
      // Until the user decides, saving still goes through the version check of the old version.
      await tester.tap(find.text('Compare'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-merge-dialog')), findsOneWidget);
      expect(find.text('Mine'), findsWidgets);
      expect(find.text('Theirs'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('merge-theirs-subject')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ticket-merge-apply')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ticket-merge-dialog')), findsNothing);
      final field = tester.widget<EditableText>(_subjectField());
      expect(field.controller.text, 'Theirs');
      expect(find.text('Compare'), findsNothing);
      await _leave(tester);
    },
  );

  testWidgets('cancelling the comparison changes nothing', (tester) async {
    final s = await _open(tester);
    await tester.enterText(_subjectField(), 'Mine');
    await tester.pump();
    s.detail = _detail(subject: 'Theirs', version: 3);
    s.live.push('updated');
    await _settle(tester);

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(_subjectField()).controller.text,
      'Mine',
    );
    expect(find.text('Compare'), findsOneWidget, reason: 'still to be decided');
    await _leave(tester);
  });
}
