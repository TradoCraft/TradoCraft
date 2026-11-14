import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/automation_page.dart';
import 'package:tradocraft_app/features/helpdesk/calendar_page.dart';
import 'package:tradocraft_app/features/helpdesk/report_charts.dart';
import 'package:tradocraft_app/features/helpdesk/reports_page.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_screen.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_split.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

const _admin = ['helpdesk.read', 'helpdesk.write', 'helpdesk.admin'];

Map<String, Object?> _team() => {
  'id': 'team1',
  'name': 'Support NL',
  'active': true,
  'members': [
    {'user_id': 'u1', 'display_name': 'Support Agent', 'is_lead': true},
  ],
  'created_at': '2026-11-01T09:00:00Z',
};

Map<String, Object?> _user() => {
  'id': 'u1',
  'display_name': 'Support Agent',
  'email': 'support@example.com',
  'roles': ['support'],
};

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => home)],
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

// ---------------------------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------------------------

Map<String, Object?> _calendar({bool enabled = false}) => {
  'team_id': null,
  'inherited': false,
  'holidays_inherited': false,
  'enabled': enabled,
  'time_zone': 'Europe/Brussels',
  'hours': [
    for (var d = 1; d <= 5; d++)
      {'weekday': d, 'start_time': '09:00', 'end_time': '17:00'},
  ],
  'holidays': [
    {'id': 'h1', 'day': '2026-11-11', 'name': 'Armistice'},
  ],
};

void main() {
  group('business hours', () {
    FakeHttp http([List<String> perms = _admin]) => FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/helpdesk/calendar': (_) => _calendar(),
      'PUT /api/v1/helpdesk/calendar': (_) => _calendar(enabled: true),
      'POST /api/v1/helpdesk/calendar/holidays': (_) => {
        'id': 'h2',
        'day': '2026-12-25',
        'name': 'Christmas',
      },
      'DELETE /api/v1/helpdesk/calendar/holidays/h1': (_) => null,
    });

    testWidgets('shows the week and the holidays', (tester) async {
      await _pump(tester, http(), const CalendarPage());
      expect(find.text('Business hours'), findsWidgets);
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
      expect(find.text('Armistice'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('start-1')))
            .controller!
            .text,
        '09:00',
      );
      // Weekend is closed: the time fields are disabled.
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('start-6'))).enabled,
        false,
      );
    });

    testWidgets('saving sends the enabled flag, zone and opening hours', (
      tester,
    ) async {
      final h = http();
      await _pump(tester, h, const CalendarPage());
      await tester.tap(find.byKey(const ValueKey('calendar-enabled')));
      await tester.enterText(find.byKey(const ValueKey('end-5')), '12:30');
      await tester.tap(find.byKey(const ValueKey('open-6')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('start-6')), '10:00');
      await tester.enterText(find.byKey(const ValueKey('end-6')), '12:00');
      await tester.ensureVisible(find.byKey(const ValueKey('save-calendar')));
      await tester.tap(find.byKey(const ValueKey('save-calendar')));
      await tester.pumpAndSettle();
      final body = h.bodies['PUT /api/v1/helpdesk/calendar'] as Map;
      expect(body['enabled'], true);
      expect(body['time_zone'], 'Europe/Brussels');
      final hours = body['hours'] as List;
      expect(hours.length, 6);
      expect((hours[4] as Map)['end_time'], '12:30');
      expect(hours.last, {
        'weekday': 6,
        'start_time': '10:00',
        'end_time': '12:00',
      });
      expect(
        find.textContaining('Open tickets were recalculated'),
        findsOneWidget,
      );
    });

    testWidgets('an invalid time is refused before anything is sent', (
      tester,
    ) async {
      final h = http();
      await _pump(tester, h, const CalendarPage());
      await tester.enterText(
        find.byKey(const ValueKey('start-1')),
        '9 o clock',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save-calendar')));
      await tester.tap(find.byKey(const ValueKey('save-calendar')));
      await tester.pumpAndSettle();
      expect(find.text('Enter times as HH:MM.'), findsOneWidget);
      expect(h.requests, isNot(contains('PUT /api/v1/helpdesk/calendar')));
    });

    testWidgets('holidays are added and removed', (tester) async {
      final h = http();
      await _pump(tester, h, const CalendarPage());
      await tester.ensureVisible(find.byKey(const ValueKey('add-holiday')));
      await tester.enterText(
        find.byKey(const ValueKey('holiday-day')),
        '2026-12-25',
      );
      await tester.enterText(
        find.byKey(const ValueKey('holiday-name')),
        'Christmas',
      );
      await tester.tap(find.byKey(const ValueKey('add-holiday')));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/helpdesk/calendar/holidays'] as Map;
      expect(body['name'], 'Christmas');
      expect(body['day'], startsWith('2026-12-25'));
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(
        h.requests,
        contains('DELETE /api/v1/helpdesk/calendar/holidays/h1'),
      );
    });

    testWidgets('a holiday without a name is not sent', (tester) async {
      final h = http();
      await _pump(tester, h, const CalendarPage());
      await tester.ensureVisible(find.byKey(const ValueKey('add-holiday')));
      await tester.enterText(
        find.byKey(const ValueKey('holiday-day')),
        '2026-12-25',
      );
      await tester.tap(find.byKey(const ValueKey('add-holiday')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a date'), findsOneWidget);
      expect(
        h.requests,
        isNot(contains('POST /api/v1/helpdesk/calendar/holidays')),
      );
    });

    testWidgets('only administrators see the settings', (tester) async {
      final h = http(['helpdesk.read', 'helpdesk.write']);
      await _pump(tester, h, const CalendarPage());
      expect(find.byKey(const ValueKey('business-hours')), findsNothing);
      expect(find.textContaining('do not have permission'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------
  // Automation rules
  // -------------------------------------------------------------------------------------------

  Map<String, Object?> rule(
    String id,
    String name, {
    bool active = true,
    bool stop = false,
  }) => {
    'id': id,
    'name': name,
    'active': active,
    'position': id == 'r1' ? 1 : 2,
    'trigger': 'created',
    'conditions': {
      'subject_contains': 'noise',
      'priorities': ['normal'],
      'owner': 'empty',
    },
    'actions': [
      {'kind': 'set_priority', 'value': 'high'},
      {'kind': 'add_tag', 'value': 'loud'},
      {'kind': 'set_team', 'team_id': 'team1'},
    ],
    'stop_on_match': stop,
    'updated_at': '2026-11-06T09:00:00Z',
  };

  group('automation rules', () {
    FakeHttp http({List<String> perms = _admin}) => FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/helpdesk/automation/rules': (_) => [
        rule('r1', 'Noise'),
        rule('r2', 'Second', active: false, stop: true),
      ],
      'GET /api/v1/helpdesk/teams': (_) => [_team()],
      'GET /api/v1/users': (_) => [_user()],
      'POST /api/v1/helpdesk/automation/rules': (_) => rule('r3', 'New'),
      'PUT /api/v1/helpdesk/automation/rules/r1': (_) => rule('r1', 'Noise'),
      'PUT /api/v1/helpdesk/automation/order': (_) => [
        rule('r2', 'Second'),
        rule('r1', 'Noise'),
      ],
      'DELETE /api/v1/helpdesk/automation/rules/r2': (_) => null,
      'GET /api/v1/tickets': (_) => {
        'items': [
          {
            'id': 't1',
            'number': 'T2026-00007',
            'subject': 'Pump noise',
            'status': 'open',
            'priority': 'normal',
            'category': 'question',
            'language': 'nl',
            'contact_name': 'Anna',
            'contact_email': 'anna@alpha.example',
            'internal': false,
            'article_count': 1,
            'created_at': '2026-11-05T10:00:00Z',
            'updated_at': '2026-11-05T10:00:00Z',
            ...ticketExtras(),
          },
        ],
        'total': 1,
      },
      'POST /api/v1/helpdesk/automation/dry-run': (_) => {
        'ticket_number': 'T2026-00007',
        'trigger': 'created',
        'rules': [
          {
            'rule_id': 'r1',
            'rule_name': 'Noise',
            'result': 'matched',
            'changes': [
              {'kind': 'set_priority', 'from': 'normal', 'to': 'high'},
            ],
          },
          {
            'rule_id': 'r2',
            'rule_name': 'Second',
            'result': 'inactive',
            'changes': <Object?>[],
          },
        ],
      },
    });

    testWidgets(
      'lists rules in order with a summary of conditions and actions',
      (tester) async {
        await _pump(tester, http(), const AutomationPage());
        expect(find.text('Noise'), findsOneWidget);
        expect(find.text('Second'), findsOneWidget);
        expect(find.textContaining('Subject ∋ "noise"'), findsNWidgets(2));
        expect(find.textContaining('Set priority: high'), findsNWidgets(2));
        expect(find.textContaining('Set team: Support NL'), findsNWidgets(2));
        expect(find.textContaining('A ticket is created'), findsNWidgets(2));
        expect(find.textContaining('Stop after this rule'), findsOneWidget);
      },
    );

    testWidgets('moving a rule sends the new order', (tester) async {
      final h = http();
      await _pump(tester, h, const AutomationPage());
      await tester.tap(find.byKey(const ValueKey('down-0')));
      await tester.pumpAndSettle();
      final body = h.bodies['PUT /api/v1/helpdesk/automation/order'] as Map;
      expect(body['ids'], ['r2', 'r1']);
    });

    testWidgets('the first rule cannot move up', (tester) async {
      await _pump(tester, http(), const AutomationPage());
      expect(
        tester.widget<IconButton>(find.byKey(const ValueKey('up-0'))).onPressed,
        isNull,
      );
    });

    testWidgets('switching a rule off keeps everything else as it was', (
      tester,
    ) async {
      final h = http();
      await _pump(tester, h, const AutomationPage());
      await tester.tap(find.byKey(const ValueKey('active-0')));
      await tester.pumpAndSettle();
      final body = h.bodies['PUT /api/v1/helpdesk/automation/rules/r1'] as Map;
      expect(body['active'], false);
      expect(body['name'], 'Noise');
      expect(body['trigger'], 'created');
      expect((body['conditions'] as Map)['subject_contains'], 'noise');
      expect((body['actions'] as List).length, 3);
    });

    testWidgets('a rule is deleted after confirmation', (tester) async {
      final h = http();
      await _pump(tester, h, const AutomationPage());
      await tester.tap(find.byKey(const ValueKey('delete-1')));
      await tester.pumpAndSettle();
      expect(
        h.requests,
        isNot(contains('DELETE /api/v1/helpdesk/automation/rules/r2')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-delete-rule')));
      await tester.pumpAndSettle();
      expect(
        h.requests,
        contains('DELETE /api/v1/helpdesk/automation/rules/r2'),
      );
    });

    testWidgets('the editor builds a rule from conditions and actions', (
      tester,
    ) async {
      final h = http();
      await _pump(tester, h, const AutomationPage());
      await tester.tap(find.byKey(const ValueKey('new-rule')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rule-name')),
        'Alpha mail',
      );
      await tester.tap(find.byKey(const ValueKey('cond-priority-high')));
      await tester.tap(find.byKey(const ValueKey('cond-priority-urgent')));
      await tester.tap(find.byKey(const ValueKey('cond-channel-email')));
      await tester.enterText(
        find.byKey(const ValueKey('cond-domain')),
        'alpha.example',
      );
      await tester.tap(find.byKey(const ValueKey('add-action')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('action-kind-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add tag').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('action-value-0')),
        'alpha',
      );
      await tester.tap(find.byKey(const ValueKey('save-rule')));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/helpdesk/automation/rules'] as Map;
      expect(body['name'], 'Alpha mail');
      expect(body['trigger'], 'created');
      expect(body['active'], true);
      final c = body['conditions'] as Map;
      expect(c['priorities'], unorderedEquals(['high', 'urgent']));
      expect(c['channels'], ['email']);
      expect(c['sender_domain'], 'alpha.example');
      expect(body['actions'], [
        {'kind': 'add_tag', 'value': 'alpha'},
      ]);
    });

    testWidgets('the editor asks for a name and shows the server message', (
      tester,
    ) async {
      final h = http();
      await _pump(tester, h, const AutomationPage());
      await tester.tap(find.byKey(const ValueKey('new-rule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-rule')));
      await tester.pumpAndSettle();
      expect(find.text('A rule needs a name.'), findsOneWidget);
      expect(
        h.requests,
        isNot(contains('POST /api/v1/helpdesk/automation/rules')),
      );
    });

    testWidgets('a dry run lists what each rule would do', (tester) async {
      final h = http();
      await _pump(tester, h, const AutomationPage());
      await tester.tap(find.byKey(const ValueKey('dry-run')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).last);
      await tester.enterText(find.byType(TextField).last, 'noise');
      await tester.pumpAndSettle();
      await tester.tap(find.text('T2026-00007 · Pump noise').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-dry-run')));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/helpdesk/automation/dry-run'] as Map;
      expect(body, {'ticket_id': 't1', 'trigger': 'created'});
      expect(find.text('applies'), findsOneWidget);
      expect(find.text('off'), findsOneWidget);
      expect(
        find.textContaining('Set priority: normal → high'),
        findsOneWidget,
      );
    });

    testWidgets('people who are not administrators get no rules', (
      tester,
    ) async {
      final h = http(perms: ['helpdesk.read', 'helpdesk.write']);
      await _pump(tester, h, const AutomationPage());
      expect(find.byKey(const ValueKey('new-rule')), findsNothing);
      expect(find.text('Noise'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------------------------
  // Split
  // -------------------------------------------------------------------------------------------

  group('split', () {
    Map<String, Object?> article(String id, String body, {int files = 0}) => {
      'id': id,
      'kind': 'email_in',
      'from_address': 'anna@alpha.example',
      'from_name': 'Anna',
      'to_addresses': ['sales@example.com'],
      'cc_addresses': <String>[],
      'subject': 'Two things',
      'body': body,
      'created_at': '2026-11-05T10:00:00Z',
      'attachments': [
        for (var i = 0; i < files; i++)
          {
            'id': 'f$i',
            'filename': 'a.pdf',
            'content_type': 'application/pdf',
            'size_bytes': 10,
            'uploader_name': 'Anna',
            'created_at': '2026-11-05T10:00:00Z',
          },
      ],
    };

    Map<String, Object?> ticket() => {
      'id': 't1',
      'number': 'T2026-00007',
      'subject': 'Two things',
      'status': 'open',
      'priority': 'normal',
      'category': 'question',
      'language': 'nl',
      'contact_name': 'Anna',
      'contact_email': 'anna@alpha.example',
      'internal': false,
      'article_count': 3,
      'created_at': '2026-11-05T10:00:00Z',
      'updated_at': '2026-11-05T10:00:00Z',
      ...ticketExtras(),
    };

    Future<FakeHttp> open(WidgetTester tester) async {
      final h = FakeHttp({
        'POST /api/v1/tickets/t1/split': (_) => {
          'ticket': {...ticket(), 'id': 't2', 'number': 'T2026-00008'},
          'articles': <Object?>[],
        },
      });
      TicketDetail? result;
      await _pump(
        tester,
        h,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showSplitDialog(
              context,
              ticket: Ticket.fromJson(ticket()),
              articles: [
                for (final a in [
                  article('a1', 'First topic'),
                  article('a2', 'Second topic: the invoice', files: 2),
                  article('a3', 'Back to the first topic'),
                ])
                  Article.fromJson(a),
              ],
            ),
            child: Text(result?.ticket.number ?? 'open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('the ticket screen offers a split only with several messages', (
      tester,
    ) async {
      for (final n in [1, 2]) {
        final h = FakeHttp({
          'GET /api/v1/me': (_) =>
              meJson(const ['helpdesk.read', 'helpdesk.write']),
          'GET /api/v1/tickets/t1': (_) => {
            'ticket': ticket(),
            'articles': [
              for (var i = 1; i <= n; i++) article('a$i', 'Message $i'),
            ],
            'watchers': <Object?>[],
            'readers': <Object?>[],
          },
          'GET /api/v1/tickets/t1/events': (_) => <Object?>[],
          'POST /api/v1/tickets/t1/read': (_) => null,
          'POST /api/v1/tickets/t1/presence': (_) => <Object?>[],
          'GET /api/v1/tickets/t1/presence': (_) => <Object?>[],
          'GET /api/v1/users': (_) => [_user()],
          'GET /api/v1/helpdesk/teams': (_) => [_team()],
          'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
          'GET /api/v1/opportunities': (_) => {'items': [], 'total': 0},
          'GET /api/v1/prepared-answers': (_) => [],
        });
        await _pump(tester, h, const TicketScreen(id: 't1'));
        final button = find.byKey(const ValueKey('split-ticket'));
        if (n == 1) {
          expect(button, findsNothing);
        } else {
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('confirm-split')), findsOneWidget);
          expect(find.byKey(const ValueKey('split-a2')), findsOneWidget);
        }
      }
    });

    testWidgets('needs a selection and keeps at least one message', (
      tester,
    ) async {
      await open(tester);
      FilledButton confirm() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-split')),
      );
      expect(confirm().onPressed, isNull, reason: 'nothing selected');
      expect(find.textContaining('2 file(s)'), findsOneWidget);
      for (final id in ['a1', 'a2', 'a3']) {
        await tester.tap(find.byKey(ValueKey('split-$id')));
        await tester.pump();
      }
      expect(confirm().onPressed, isNull, reason: 'everything selected');
      expect(
        find.textContaining('At least one message must stay'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('split-a1')));
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
    });

    testWidgets('sends the chosen messages and subject', (tester) async {
      final h = await open(tester);
      await tester.tap(find.byKey(const ValueKey('split-a2')));
      await tester.enterText(
        find.byKey(const ValueKey('split-subject')),
        'Invoice',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-split')));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/tickets/t1/split'] as Map;
      expect(body['article_ids'], ['a2']);
      expect(body['subject'], 'Invoice');
    });

    testWidgets('a refusal from the server stays in the dialog', (
      tester,
    ) async {
      final h = await open(tester);
      h.routes.remove('POST /api/v1/tickets/t1/split');
      await tester.tap(find.byKey(const ValueKey('split-a2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-split')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirm-split')), findsOneWidget);
      expect(
        find.textContaining('POST /api/v1/tickets/t1/split'),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------------------------
  // Reports
  // -------------------------------------------------------------------------------------------

  group('reports', () {
    Map<String, Object?> report({String basis = 'business'}) => {
      'from': '2026-11-01',
      'to': '2026-11-07',
      'group': 'day',
      'basis': basis,
      'volume': [
        for (var d = 1; d <= 7; d++)
          {
            'period': '2026-11-0$d',
            'created': d == 2 ? 4 : 0,
            'closed': d == 3 ? 2 : 0,
          },
      ],
      'backlog_by_status': [
        {'key': 'open', 'label': 'open', 'count': 3},
        {'key': 'pending_customer', 'label': 'pending_customer', 'count': 1},
      ],
      'backlog_by_priority': [
        {'key': 'normal', 'label': 'normal', 'count': 4},
      ],
      'backlog_by_team': [
        {'key': 'team1', 'label': 'Support NL', 'count': 3},
        {'key': '', 'label': '', 'count': 1},
      ],
      'backlog_by_owner': <Object?>[],
      'first_response': {
        'count': 2,
        'average_minutes': 60.0,
        'p90_minutes': 90.0,
      },
      'resolution': {
        'count': 2,
        'average_minutes': 420.0,
        'p90_minutes': 600.0,
      },
      'sla': {
        'tickets': 4,
        'breached': 1,
        'compliant': 3,
        'compliance_percent': 75.0,
      },
      'breaches_by_team': [
        {'team_id': 'team1', 'team': 'Support NL', 'tickets': 3, 'breached': 1},
      ],
      'csat': {'responses': 2, 'good': 1, 'bad': 1, 'average_percent': 50.0},
      'top_categories': [
        {'key': 'question', 'label': 'question', 'count': 3},
      ],
      'top_tags': [
        {'key': 'warranty', 'label': 'warranty', 'count': 2},
      ],
      'time_by_user': [
        {
          'user_id': 'u1',
          'name': 'Support Agent',
          'total_minutes': 50,
          'billable_minutes': 20,
          'non_billable_minutes': 30,
        },
      ],
      'time_billable_minutes': 20,
      'time_non_billable_minutes': 30,
    };

    FakeHttp http({String basis = 'business'}) => FakeHttp({
      'GET /api/v1/me': (_) => meJson(const ['helpdesk.read']),
      'GET /api/v1/helpdesk/reports': (_) => report(basis: basis),
      'GET /api/v1/helpdesk/reports/export': (_) =>
          'period,created,closed\r\n2026-11-02,4,0\r\n',
      'GET /api/v1/helpdesk/teams': (_) => [_team()],
      'GET /api/v1/users': (_) => [_user()],
    });

    testWidgets('shows the key figures, the chart and the tables', (
      tester,
    ) async {
      await _pump(tester, http(), const ReportsPage());
      expect(find.text('75 %'), findsOneWidget);
      expect(find.textContaining('1 of 4 breached'), findsOneWidget);
      expect(find.text('1 h 00 min'), findsWidgets);
      expect(
        find.textContaining('90% within: 1 h 30 min · business hours'),
        findsOneWidget,
      );
      expect(find.text('7 h 00 min'), findsOneWidget);
      expect(find.text('50 %'), findsOneWidget);
      expect(find.text('2 responses'), findsOneWidget);
      expect(find.byKey(const ValueKey('volume-chart')), findsOneWidget);
      expect(find.text('Support NL'), findsWidgets);
      expect(find.text('warranty'), findsOneWidget);
      expect(find.text('Support Agent'), findsOneWidget);
      expect(find.textContaining('Billable: 0 h 20 min'), findsNothing);
    });

    testWidgets('says when times are elapsed time', (tester) async {
      await _pump(tester, http(basis: 'elapsed'), const ReportsPage());
      expect(find.textContaining('elapsed time'), findsWidgets);
    });

    testWidgets('filters go to the server', (tester) async {
      final h = http();
      await _pump(tester, h, const ReportsPage());
      await tester.tap(find.byKey(const ValueKey('report-team')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support NL').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Per week'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-7')));
      await tester.pumpAndSettle();
      final q = h.queries.last;
      expect(q['team_id'], 'team1');
      expect(q['group'], 'week');
      final from = DateTime.parse(q['from'] as String);
      final to = DateTime.parse(q['to'] as String);
      expect(to.difference(from).inDays, 6);
    });

    testWidgets('a table is copied as CSV', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final h = http();
      await _pump(tester, h, const ReportsPage());
      await tester.ensureVisible(find.byKey(const ValueKey('csv-volume')));
      await tester.tap(find.byKey(const ValueKey('csv-volume')));
      await tester.pumpAndSettle();
      expect(h.queries.last['table'], 'volume');
      // The fake server wraps every body in JSON; a real one sends the CSV as it is.
      expect(
        jsonDecode(copied!),
        'period,created,closed\r\n2026-11-02,4,0\r\n',
      );
      expect(find.text('CSV copied to the clipboard'), findsOneWidget);
    });

    testWidgets('a server error is shown instead of the report', (
      tester,
    ) async {
      final h = http();
      h.routes.remove('GET /api/v1/helpdesk/reports');
      await _pump(tester, h, const ReportsPage());
      expect(
        find.textContaining('GET /api/v1/helpdesk/reports'),
        findsOneWidget,
      );
    });
  });

  test('bar heights scale to the tallest value', () {
    expect(VolumePainter.barHeight(0, 10, 100), 0);
    expect(VolumePainter.barHeight(5, 10, 100), 50);
    expect(VolumePainter.barHeight(10, 10, 100), 100);
    expect(VolumePainter.barHeight(3, 0, 100), 0, reason: 'no data, no bars');
  });
}
