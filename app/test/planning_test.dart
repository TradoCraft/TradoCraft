import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/planning/board_model.dart';
import 'package:tradocraft_app/features/planning/planning_adapter.dart';
import 'package:tradocraft_app/features/planning/planning_page.dart';
import 'package:tradocraft_app/features/planning/planning_settings_page.dart';
import 'package:tradocraft_app/features/planning/resource_board.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

// The week of Monday 9 November 2026.
final _monday = DateTime(2026, 11, 9);

String _utc(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute).toUtc().toIso8601String();

Map<String, Object?> _job(
  String id,
  String number, {
  String? start,
  String? end,
  List<String> techs = const [],
  List<String> skills = const [],
  String priority = 'normal',
  String status = 'planned',
}) => {
  'id': id,
  'number': number,
  'title': 'Job $number',
  'kind': 'maintenance',
  'status': status,
  'priority': priority,
  'customer_id': 'c1',
  'customer_name': 'Alpha Installaties NV',
  'city': 'Antwerpen',
  'due_date': null,
  'scheduled_start': start,
  'scheduled_end': end,
  'technician_ids': techs,
  'required_skill_ids': skills,
};

List<Map<String, Object?>> _hours(String userId) => [
  for (var d = 1; d <= 5; d++) ...[
    {
      'id': 'h$userId$d-1',
      'user_id': null,
      'weekday': d,
      'start_time': '08:00:00',
      'end_time': '12:00:00',
    },
    {
      'id': 'h$userId$d-2',
      'user_id': null,
      'weekday': d,
      'start_time': '13:00:00',
      'end_time': '17:00:00',
    },
  ],
];

Map<String, Object?> _technician(
  String id,
  String name, {
  List<Map<String, Object?>> absences = const [],
  List<Map<String, Object?>> skills = const [],
}) => {
  'user_id': id,
  'display_name': name,
  'skills': skills,
  'working_hours': _hours(id),
  'hours_are_default': true,
  'absences': absences,
};

Map<String, Object?> _board() => {
  'from': '2026-11-09',
  'to': '2026-11-15',
  'settings': {
    'travel_buffer_minutes': 15,
    'default_job_minutes': 120,
    'timezone': 'Europe/Brussels',
  },
  'skills': [
    {'id': 's1', 'code': 'HVAC', 'name': 'HVAC'},
  ],
  'technicians': [
    _technician(
      't1',
      'Tom Technician',
      absences: [
        {
          'id': 'a1',
          'user_id': 't1',
          'user_name': 'Tom Technician',
          'from_date': '2026-11-10',
          'to_date': '2026-11-11',
          'kind': 'vacation',
          'note': '',
        },
      ],
    ),
    _technician(
      't2',
      'Tina Technician',
      skills: [
        {'skill_id': 's1', 'code': 'HVAC', 'name': 'HVAC', 'level': 2},
      ],
    ),
  ],
  'jobs': [
    _job(
      'j1',
      'J2026-00001',
      start: _utc(9, 9),
      end: _utc(9, 11),
      techs: ['t1'],
    ),
  ],
  'backlog': [
    _job('b1', 'J2026-00002', priority: 'urgent', skills: ['s1']),
  ],
};

/// A server for the board: conflicts are reported for Tom (t1) only.
FakeHttp _server({
  List<String> permissions = const [
    'planning.read',
    'planning.write',
    'planning.admin',
  ],
}) {
  late FakeHttp http;
  Object? schedule(Object? body) {
    final techs = ((body as Map)['technician_ids'] as List).cast<String>();
    final dry = http.queries.last['dry_run'] == true;
    final conflicts = techs.contains('t1')
        ? [
            {
              'kind': 'double_booked',
              'severity': 'error',
              'technician_id': 't1',
              'message_key': 'planning.conflict.double_booked',
              'other_job_id': 'j1',
            },
          ]
        : <Object?>[];
    return {'applied': !dry, 'conflicts': conflicts, 'job': null};
  }

  http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(permissions),
    'GET /api/v1/planning/board': (_) => _board(),
    'PUT /api/v1/planning/jobs/b1/schedule': schedule,
    'PUT /api/v1/planning/jobs/j1/schedule': schedule,
    'GET /api/v1/planning/suggestions/b1': (_) => [],
  });
  return http;
}

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http, {
  Size size = const Size(1700, 1000),
  Widget? home,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => home ?? PlanningPage(initialDay: _monday),
      ),
      GoRoute(
        path: '/jobs/:id',
        builder: (_, s) => Text('job page ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/planning/settings',
        builder: (_, _) => const Text('settings page'),
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

/// Picks up the backlog card and carries it over the Monday cell of [row] at [hour]:[minute].
Future<TestGesture> _dragBacklogTo(
  WidgetTester tester,
  String row,
  int hour,
  int minute,
) async {
  final card = tester.getCenter(find.byKey(const ValueKey('backlog-b1')));
  final cell = tester.getRect(find.byKey(ValueKey('cell-$row-2026-11-09')));
  // The axis shows 07:00-19:00 for these working hours.
  final x =
      cell.left + ((hour * 60 + minute) - 7 * 60) * (cell.width / (12 * 60));
  final g = await tester.startGesture(card);
  await tester.pump(const Duration(milliseconds: 250));
  await g.moveBy(const Offset(0, 6));
  await tester.pump();
  await g.moveTo(Offset(x, cell.center.dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  return g;
}

void main() {
  testWidgets(
    'renders technicians, the job block, the backlog and the shading',
    (tester) async {
      final http = _server();
      await _pump(tester, http);
      expect(find.text('Tom Technician'), findsOneWidget);
      expect(find.text('Tina Technician'), findsOneWidget);
      expect(
        find.textContaining('J2026-00001 Job J2026-00001'),
        findsOneWidget,
      );
      // The backlog holds the unplanned job with its required skill.
      expect(find.byKey(const ValueKey('backlog-b1')), findsOneWidget);
      expect(find.textContaining('J2026-00002'), findsOneWidget);
      expect(find.text('To plan (1)'), findsOneWidget);
      // The board was requested for the whole week.
      expect(
        http.queries.firstWhere((q) => q.containsKey('from'))['from'],
        startsWith('2026-11-09'),
      );
      expect(
        http.queries.firstWhere((q) => q.containsKey('to'))['to'],
        startsWith('2026-11-15'),
      );

      // Out-of-hours time is shaded on a working day, the weekend completely; the absence on its days.
      expect(
        find.byKey(const ValueKey('shade-offHours-t2-2026-11-09')),
        findsNWidgets(3),
      );
      expect(
        find.byKey(const ValueKey('shade-offHours-t2-2026-11-14')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shade-absence-t1-2026-11-10')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shade-absence-t1-2026-11-11')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shade-absence-t1-2026-11-12')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('shade-absence-t2-2026-11-10')),
        findsNothing,
      );
      expect(find.text('Vacation'), findsWidgets);
    },
  );

  testWidgets('switches between week and day, moves, and filters by skill', (
    tester,
  ) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(http.queries.last['from'], startsWith('2026-11-09'));
    expect(http.queries.last['to'], startsWith('2026-11-09'));
    expect(find.byKey(const ValueKey('cell-t1-2026-11-10')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('next')));
    await tester.pumpAndSettle();
    expect(http.queries.last['from'], startsWith('2026-11-10'));
    await tester.tap(find.byKey(const ValueKey('prev')));
    await tester.tap(find.byKey(const ValueKey('prev')));
    await tester.pumpAndSettle();
    expect(http.queries.last['from'], startsWith('2026-11-08'));
    await tester.tap(find.byKey(const ValueKey('today')));
    await tester.pumpAndSettle();
    final today = DateTime.now();
    expect(
      http.queries.last['from'],
      startsWith(dayKey(DateTime(today.year, today.month, today.day))),
    );

    // Only technicians with the skill remain.
    await tester.tap(find.byKey(const ValueKey('skill-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HVAC').last);
    await tester.pumpAndSettle();
    expect(find.text('Tina Technician'), findsOneWidget);
    expect(find.text('Tom Technician'), findsNothing);
  });

  testWidgets(
    'dragging over a busy technician shows the conflict banner from a dry run',
    (tester) async {
      final http = _server();
      await _pump(tester, http);
      final g = await _dragBacklogTo(tester, 't1', 10, 0);
      expect(
        find.byKey(const ValueKey('planning-conflict-banner')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Tom Technician has another job at that time'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ghost')), findsOneWidget);
      final dry = http.queries.lastIndexWhere((q) => q['dry_run'] == true);
      expect(dry, isNonNegative);
      // Nothing was saved while dragging.
      expect(
        http.requests
            .where((r) => r == 'PUT /api/v1/planning/jobs/b1/schedule')
            .length,
        1,
      );
      await g.cancel();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('planning-conflict-banner')),
        findsNothing,
      );
    },
  );

  testWidgets('dropping on a conflict asks first and then saves with force', (
    tester,
  ) async {
    final http = _server();
    await _pump(tester, http);
    final g = await _dragBacklogTo(tester, 't1', 10, 0);
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Schedule with conflicts?'), findsOneWidget);
    // Declining changes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      http.queries
          .where((q) => q['dry_run'] != true && q.containsKey('force'))
          .length,
      0,
    );

    final g2 = await _dragBacklogTo(tester, 't1', 10, 0);
    await g2.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule anyway'));
    await tester.pumpAndSettle();
    final saved = http.queries.lastIndexWhere((q) => q['force'] == true);
    expect(saved, isNonNegative);
    expect(http.queries[saved].containsKey('dry_run'), isFalse);
    expect(find.text('Job scheduled.'), findsOneWidget);
  });

  testWidgets(
    'dropping on a free technician saves at once, snapped to 15 minutes',
    (tester) async {
      final http = _server();
      await _pump(tester, http);
      // 10:07 snaps to 10:00; the urgent job takes the default two hours.
      final g = await _dragBacklogTo(tester, 't2', 10, 7);
      expect(find.textContaining('No conflicts'), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('Schedule with conflicts?'), findsNothing);
      final body = http.bodies['PUT /api/v1/planning/jobs/b1/schedule'] as Map;
      expect(body['technician_ids'], ['t2']);
      expect(
        DateTime.parse(body['scheduled_start'] as String).toLocal(),
        DateTime(2026, 11, 9, 10),
      );
      expect(
        DateTime.parse(body['scheduled_end'] as String).toLocal(),
        DateTime(2026, 11, 9, 12),
      );
      expect(http.queries.last.containsKey('dry_run'), isFalse);
      // The board is reloaded after saving.
      expect(http.requests.last, 'GET /api/v1/planning/board');
    },
  );

  testWidgets('the Plan button schedules a job without dragging', (
    tester,
  ) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule J2026-00002'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tech-t2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No conflicts'), findsOneWidget);
    // Choosing Tom shows his conflict in the dialog.
    await tester.tap(find.byKey(const ValueKey('tech-t1')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Tom Technician has another job'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tech-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-schedule')));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/planning/jobs/b1/schedule'] as Map;
    expect(body['technician_ids'], ['t2']);
    final start = DateTime.parse(body['scheduled_start'] as String).toLocal();
    expect(start.hour, 9);
    expect(
      DateTime.parse(body['scheduled_end'] as String)
          .difference(DateTime.parse(body['scheduled_start'] as String)),
      const Duration(hours: 2),
    );
    expect(find.text('Schedule J2026-00002'), findsNothing);
  });

  testWidgets(
    'dragging a block to another technician moves it and keeps its time',
    (tester) async {
      final http = _server();
      await _pump(tester, http);
      final block = tester.getCenter(
        find.byKey(const ValueKey('block-j1:t1-2026-11-09')),
      );
      final other = tester.getRect(
        find.byKey(const ValueKey('cell-t2-2026-11-09')),
      );
      final g = await tester.startGesture(block);
      await tester.pump(const Duration(milliseconds: 250));
      await g.moveBy(const Offset(0, 6));
      await tester.pump();
      await g.moveTo(Offset(block.dx, other.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/planning/jobs/j1/schedule'] as Map;
      expect(body['technician_ids'], ['t2']);
      expect(
        DateTime.parse(body['scheduled_start'] as String).toLocal(),
        DateTime(2026, 11, 9, 9),
      );
      expect(
        DateTime.parse(body['scheduled_end'] as String).toLocal(),
        DateTime(2026, 11, 9, 11),
      );
    },
  );

  testWidgets('tapping a block opens the job', (tester) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.textContaining('J2026-00001 Job J2026-00001'));
    await tester.pumpAndSettle();
    expect(find.text('job page j1'), findsOneWidget);
  });

  testWidgets('on a phone the board becomes an agenda of the day', (
    tester,
  ) async {
    final http = _server();
    await _pump(tester, http, size: const Size(420, 900));
    expect(find.byKey(const ValueKey('planning-agenda')), findsOneWidget);
    expect(find.byType(ResourceBoard), findsNothing);
    expect(find.byKey(const ValueKey('agenda-j1')), findsOneWidget);
    expect(find.text('Tom Technician'), findsOneWidget);
    // No week switch on a phone, the board asked for one day.
    expect(find.text('Week'), findsNothing);
    expect(
      http.queries.firstWhere((q) => q.containsKey('from'))['to'],
      startsWith('2026-11-09'),
    );
    // The backlog is below, with a Plan button.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('backlog-b1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Plan'), findsOneWidget);
    // Tom is on vacation the next day.
    await tester.tap(find.byKey(const ValueKey('next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('absence-t1')), findsOneWidget);
  });

  testWidgets('the settings page saves the travel buffer', (tester) async {
    final http = _server();
    http.routes['GET /api/v1/planning/settings'] = (_) => {
      'travel_buffer_minutes': 15,
      'default_job_minutes': 120,
      'timezone': 'Europe/Brussels',
    };
    http.routes['PUT /api/v1/planning/settings'] = (b) => b;
    http.routes['GET /api/v1/planning/absences'] = (_) => [];
    http.routes['GET /api/v1/planning/skills'] = (_) => [];
    http.routes['GET /api/v1/planning/working-hours'] = (_) => [];
    await _pump(tester, http, home: const PlanningSettingsPage());
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('buffer')), '30');
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/planning/settings'] as Map;
    expect(body['travel_buffer_minutes'], 30);
    expect(body['default_job_minutes'], 120);
    expect(body['timezone'], 'Europe/Brussels');
  });

  testWidgets('working hours are saved with several blocks per day', (
    tester,
  ) async {
    final http = _server();
    http.routes['GET /api/v1/planning/working-hours'] = (_) => [
      {
        'id': 'x',
        'user_id': null,
        'weekday': 1,
        'start_time': '08:00:00',
        'end_time': '12:00:00',
      },
    ];
    http.routes['PUT /api/v1/planning/working-hours'] = (_) => [];
    http.routes['GET /api/v1/planning/absences'] = (_) => [];
    await _pump(tester, http, home: const PlanningSettingsPage());
    await tester.tap(find.text('Working hours'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-block-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-hours')));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/planning/working-hours'] as Map;
    expect(body['user_id'], isNull);
    expect(body['slots'], [
      {'weekday': 1, 'start_time': '08:00', 'end_time': '12:00'},
      {'weekday': 1, 'start_time': '13:00', 'end_time': '17:00'},
    ]);
  });

  test('overlapping blocks get their own lanes', () {
    DateTime t(int h, [int m = 0]) => DateTime(2026, 11, 9, h, m);
    final r = assignLanes([
      (t(9), t(11)),
      (t(10), t(12)),
      (t(11), t(12)),
      (t(13), t(14)),
    ]);
    expect(r.lanes, [0, 1, 0, 0]);
    expect(r.count, 2);
    expect(assignLanes(const []).count, 1);
  });

  test('a dropped block replaces only the technician it came from', () {
    final job = BoardJob.fromJson(_job('j', 'J1', techs: ['a', 'b']));
    expect(techniciansAfterDrop(job, 'a', 'c'), ['b', 'c']);
    expect(techniciansAfterDrop(job, 'a', 'b'), ['b']);
    expect(techniciansAfterDrop(job, null, 'c'), ['c']);
  });

  test('the axis snaps to quarter hours', () {
    const axis = BoardAxis(startMinute: 420, endMinute: 1140, pxPerMinute: 2);
    expect(axis.minuteAt(0), 420);
    expect(
      axis.minuteAt(2 * 187),
      420 + 180,
    ); // 187 min after 07:00 is 10:07 -> 10:00
    expect(axis.minuteAt(2 * 188), 420 + 195); // 10:08 -> 10:15
    expect(axis.xOf(480), 120);
  });
}
