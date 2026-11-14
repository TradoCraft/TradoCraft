import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/calendar_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

const _admin = ['helpdesk.read', 'helpdesk.write', 'helpdesk.admin'];

Map<String, Object?> _calendar({
  String? teamId,
  bool inherited = false,
  bool holidaysInherited = false,
  String end = '17:00',
}) => {
  'team_id': teamId,
  'inherited': inherited,
  'holidays_inherited': holidaysInherited,
  'enabled': true,
  'time_zone': 'Europe/Brussels',
  'hours': [
    for (var d = 1; d <= 5; d++)
      {'weekday': d, 'start_time': '09:00', 'end_time': end},
  ],
  'holidays': [
    {'id': 'h1', 'day': '2026-11-11', 'name': 'Armistice'},
  ],
};

FakeHttp _http({required Map<String, Object?> Function(Object?) calendar}) =>
    FakeHttp({
      'GET /api/v1/me': (_) => meJson(_admin),
      'GET /api/v1/helpdesk/teams': (_) => [
        {
          'id': 'team1',
          'name': 'Support NL',
          'active': true,
          'members': <Object?>[],
          'created_at': '2026-11-01T09:00:00Z',
        },
      ],
      'GET /api/v1/helpdesk/calendar': calendar,
      'PUT /api/v1/helpdesk/calendar': (_) =>
          _calendar(teamId: 'team1', end: '12:00'),
      'DELETE /api/v1/helpdesk/calendar': (_) =>
          _calendar(teamId: 'team1', inherited: true, holidaysInherited: true),
    });

Future<void> _pump(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const CalendarPage())],
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

Future<void> _selectTeam(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('calendar-team')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Support NL').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a team without a calendar shows the inherited company one', (
    tester,
  ) async {
    final h = _http(
      calendar: (_) =>
          _calendar(teamId: 'team1', inherited: true, holidaysInherited: true),
    );
    await _pump(tester, h);
    // The company calendar is asked for without a team.
    expect(h.queries.last['team_id'], isNull);
    await _selectTeam(tester);
    expect(h.queries.last['team_id'], 'team1');
    expect(find.byKey(const ValueKey('calendar-inherited')), findsOneWidget);
    expect(find.text('Armistice'), findsOneWidget);
    // The company's holidays cannot be removed from the team's view, and none can be added until
    // the team has a calendar of its own.
    expect(find.byTooltip('Remove'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('add-holiday')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('use-company-calendar')), findsNothing);
  });

  testWidgets('saving for a team sends its id and the company calendar can be '
      'restored', (tester) async {
    final h = _http(
      calendar: (_) => _calendar(teamId: 'team1', end: '12:00'),
    );
    await _pump(tester, h);
    await _selectTeam(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('save-calendar')));
    await tester.tap(find.byKey(const ValueKey('save-calendar')));
    await tester.pumpAndSettle();
    final put = h.requests.indexOf('PUT /api/v1/helpdesk/calendar');
    expect(put, isNonNegative);
    expect(h.queries[put]['team_id'], 'team1');

    await tester.ensureVisible(
      find.byKey(const ValueKey('use-company-calendar')),
    );
    await tester.tap(find.byKey(const ValueKey('use-company-calendar')));
    await tester.pumpAndSettle();
    final del = h.requests.indexOf('DELETE /api/v1/helpdesk/calendar');
    expect(del, isNonNegative);
    expect(h.queries[del]['team_id'], 'team1');
  });
}
