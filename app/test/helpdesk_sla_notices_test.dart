import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/sla_notices_card.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Future<void> _pump(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: SlaNoticesCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FakeHttp _http(List<Object?> rules) => FakeHttp({
  'GET /api/v1/helpdesk/sla-notices': (_) => {'rules': rules},
  'PUT /api/v1/helpdesk/sla-notices': (b) => b,
  'GET /api/v1/helpdesk/teams': (_) => [
    {
      'id': 'team1',
      'name': 'Support NL',
      'active': true,
      'members': <Object?>[],
      'created_at': '2026-11-01T09:00:00Z',
    },
  ],
});

void main() {
  testWidgets('says that nothing is sent without a rule', (tester) async {
    await _pump(tester, _http([]));
    expect(find.text('No notices are sent to customers.'), findsOneWidget);
  });

  testWidgets('adds a rule for a team and priority and saves it', (
    tester,
  ) async {
    final http = _http([]);
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('notice-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notice-team-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support NL').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notice-priority-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('urgent').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notice-breach-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notice-save')));
    await tester.pumpAndSettle();
    expect(http.bodies['PUT /api/v1/helpdesk/sla-notices'], {
      'rules': [
        {
          'team_id': 'team1',
          'priority': 'urgent',
          'ack_enabled': true,
          'breach_enabled': true,
        },
      ],
    });
  });

  testWidgets('shows the saved rules and removes one', (tester) async {
    final http = _http([
      {
        'ack_enabled': true,
        'breach_enabled': false,
      },
      {
        'priority': 'low',
        'ack_enabled': false,
        'breach_enabled': true,
      },
    ]);
    await _pump(tester, http);
    expect(find.byKey(const ValueKey('notice-ack-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notice-remove-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notice-save')));
    await tester.pumpAndSettle();
    expect(http.bodies['PUT /api/v1/helpdesk/sla-notices'], {
      'rules': [
        {
          'priority': 'low',
          'ack_enabled': false,
          'breach_enabled': true,
        },
      ],
    });
  });
}
