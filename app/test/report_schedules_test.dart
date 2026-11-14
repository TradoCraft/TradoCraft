import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/reports/report_schedules_page.dart';
import 'package:tradocraft_app/features/reports/reports_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

const _manager = ['reports.read', 'reports.write', 'reports.schedule'];

Map<String, Object?> _schedule({
  String id = 's1',
  String name = 'Weekly volume',
  String source = 'helpdesk',
  bool active = true,
  String? status,
  String? error,
}) => {
  'id': id,
  'name': name,
  'source': source,
  'report_id': source == 'custom' ? 'r1' : null,
  'report_name': source == 'custom' ? 'Total by status' : null,
  'helpdesk': source == 'helpdesk'
      ? {'table': 'volume', 'period': 'last_week'}
      : null,
  'frequency': 'weekly',
  'weekday': 1,
  'day_of_month': null,
  'send_time': '07:30',
  'time_zone': 'Europe/Brussels',
  'format': 'pdf',
  'user_ids': ['u1'],
  'addresses': ['boss@example.com'],
  'active': active,
  'owner_id': 'u1',
  'owner_name': 'Manager',
  'next_run_at': '2027-01-18T06:30:00Z',
  'last_run_at': status == null ? null : '2027-01-11T06:30:00Z',
  'last_status': status,
  'last_error': error,
  'created_at': '2027-01-01T09:00:00Z',
  'updated_at': '2027-01-01T09:00:00Z',
};

Map<String, Object?> _savedReport() => {
  'id': 'r1',
  'name': 'Total by status',
  'description': '',
  'object': 'quotation',
  'definition': {
    'object': 'quotation',
    'columns': [
      {'field': 'quotation.number'},
    ],
  },
  'shared': true,
  'owner_id': 'u1',
  'owner_name': 'Manager',
  'mine': true,
  'created_at': '2027-01-01T09:00:00Z',
  'updated_at': '2027-01-01T09:00:00Z',
};

FakeHttp _http(List<Object?> schedules, {List<String> perms = _manager}) =>
    FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/report-schedules': (_) => schedules,
      'GET /api/v1/custom-reports': (_) => [_savedReport()],
      'GET /api/v1/users': (_) => [
        {
          'id': 'u1',
          'display_name': 'Manager',
          'email': 'manager@example.com',
          'roles': ['sales_manager'],
        },
        {
          'id': 'u2',
          'display_name': 'Support Agent',
          'email': 'support@example.com',
          'roles': ['support'],
        },
      ],
      'POST /api/v1/report-schedules': (_) => _schedule(),
      'PUT /api/v1/report-schedules/s1': (_) => _schedule(),
      'DELETE /api/v1/report-schedules/s1': (_) => null,
      'POST /api/v1/report-schedules/s1/send': (_) => {'mails': 2},
    });

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(path: '/reports', builder: (_, _) => const Text('LIST PAGE')),
      GoRoute(
        path: '/reports/schedules',
        builder: (_, _) => const Text('SCHEDULES PAGE'),
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

void main() {
  testWidgets('lists the schedules with when, format, recipients and state', (
    tester,
  ) async {
    await _pump(
      tester,
      _http([
        _schedule(),
        _schedule(
          id: 's2',
          name: 'Customer list',
          source: 'custom',
          active: false,
          status: 'failed',
          error: 'the owner is no longer active',
        ),
      ]),
      const ReportSchedulesPage(),
    );
    expect(find.text('Weekly volume'), findsOneWidget);
    expect(
      find.text('Weekly, Monday 07:30 · PDF · 2 recipients'),
      findsNWidgets(2),
    );
    expect(find.textContaining('Helpdesk report: volume'), findsOneWidget);
    expect(
      find.textContaining('Saved report: Total by status'),
      findsOneWidget,
    );
    expect(find.text('Paused'), findsOneWidget);
    expect(
      find.textContaining('the owner is no longer active'),
      findsOneWidget,
    );
  });

  testWidgets('creates a helpdesk schedule with recipients', (tester) async {
    final http = _http([]);
    await _pump(tester, http, const ReportSchedulesPage());
    expect(find.text('No reports are scheduled.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-schedule')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('schedule-name')),
      'Volume',
    );
    await tester.tap(find.byKey(const ValueKey('schedule-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Helpdesk report').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-user-u2')));
    await tester.enterText(
      find.byKey(const ValueKey('schedule-addresses')),
      'ops@example.com, boss@example.com',
    );
    await tester.tap(find.byKey(const ValueKey('save-schedule')));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/report-schedules'] as Map;
    expect(body['name'], 'Volume');
    expect(body['source'], 'helpdesk');
    expect(body['helpdesk'], {'table': 'volume', 'period': 'last_7_days'});
    expect(body['frequency'], 'weekly');
    expect(body['weekday'], 1);
    expect(body['send_time'], '07:00');
    expect(body['format'], 'pdf');
    expect(body['user_ids'], ['u2']);
    expect(body['addresses'], ['ops@example.com', 'boss@example.com']);
    expect(body['report_id'], isNull);
  });

  testWidgets('a schedule needs a recipient before anything is sent', (
    tester,
  ) async {
    final http = _http([]);
    await _pump(tester, http, const ReportSchedulesPage());
    await tester.tap(find.byKey(const ValueKey('new-schedule')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('schedule-name')), 'X');
    await tester.tap(find.byKey(const ValueKey('save-schedule')));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one recipient.'), findsOneWidget);
    expect(http.requests, isNot(contains('POST /api/v1/report-schedules')));
  });

  testWidgets('pauses, sends now and deletes after confirmation', (
    tester,
  ) async {
    final http = _http([_schedule()]);
    await _pump(tester, http, const ReportSchedulesPage());
    await tester.tap(find.byKey(const ValueKey('schedule-active-s1')));
    await tester.pumpAndSettle();
    expect(
      (http.bodies['PUT /api/v1/report-schedules/s1'] as Map)['active'],
      false,
    );
    await tester.tap(find.byKey(const ValueKey('schedule-send-s1')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/report-schedules/s1/send'));
    expect(find.text('2 mails queued.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('schedule-delete-s1')));
    await tester.pumpAndSettle();
    expect(
      http.requests,
      isNot(contains('DELETE /api/v1/report-schedules/s1')),
    );
    await tester.tap(find.byKey(const ValueKey('schedule-confirm-delete')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('DELETE /api/v1/report-schedules/s1'));
  });

  testWidgets('a person without the permission gets no schedules', (
    tester,
  ) async {
    final http = _http([_schedule()], perms: const ['reports.read']);
    await _pump(tester, http, const ReportSchedulesPage());
    expect(find.text('Weekly volume'), findsNothing);
    expect(find.byKey(const ValueKey('new-schedule')), findsNothing);
    expect(http.requests, isNot(contains('GET /api/v1/report-schedules')));
  });

  testWidgets(
    'the saved reports page links to the schedules only for those who may',
    (tester) async {
      await _pump(tester, _http([]), const SavedReportsPage());
      expect(find.byKey(const ValueKey('open-schedules')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-schedules')));
      await tester.pumpAndSettle();
      expect(find.text('SCHEDULES PAGE'), findsOneWidget);
      await _pump(
        tester,
        _http([], perms: const ['reports.read', 'reports.write']),
        const SavedReportsPage(),
      );
      expect(find.byKey(const ValueKey('open-schedules')), findsNothing);
    },
  );
}
