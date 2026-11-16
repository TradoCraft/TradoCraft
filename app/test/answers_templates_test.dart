import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/answers_page.dart';
import 'package:tradocraft_app/features/helpdesk/automation_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _answer(String code, {String kind = 'reply', String? teamId}) => {
  'id': 'a-$code',
  'code': code,
  'name': 'Answer $code',
  'category': null,
  'kind': kind,
  'team_id': teamId,
  'keywords': <String>['pump'],
  'active': true,
  'updated_at': '2026-11-16T09:00:00Z',
  'texts': [
    {'language': 'en', 'subject': 'Re', 'body': 'Hello'},
  ],
};

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => home)]);
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
  testWidgets('the answer editor saves kind, team and keywords', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/helpdesk/teams': (_) => [
        {'id': 'team1', 'name': 'R&D', 'active': true, 'members': [], 'created_at': '2026-11-01T09:00:00Z'},
      ],
      'GET /api/v1/prepared-answers/placeholders': (_) => ['ticket.number', 'team.name'],
      'POST /api/v1/prepared-answers': (_) => _answer('fw', kind: 'internal_note', teamId: 'team1'),
    });
    await _pump(tester, http, const Scaffold(body: AnswerEditor()));
    await tester.enterText(find.widgetWithText(TextField, 'Code'), 'fw');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Firmware');
    await tester.enterText(find.byKey(const ValueKey('answer-keywords')), 'Firmware, update');
    await tester.tap(find.byKey(const ValueKey('answer-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internal note').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-team')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('R&D').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Text').first, 'Body');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent = http.bodies['POST /api/v1/prepared-answers'] as Map;
    expect(sent['kind'], 'internal_note');
    expect(sent['team_id'], 'team1');
    expect(sent['keywords'], ['firmware', 'update']);
  });

  testWidgets(
      'choosing a template in a send_email action stores its id and hides the inline text',
      (tester) async {
    final http = FakeHttp({
      'GET /api/v1/helpdesk/teams': (_) => <Object?>[],
      'GET /api/v1/users': (_) => <Object?>[],
      'GET /api/v1/prepared-answers': (_) => [_answer('ops')],
      'POST /api/v1/helpdesk/automation/rules': (_) => {
        'id': 'r1',
        'name': 'Notify',
        'active': true,
        'trigger': 'ticket_created',
        'stop_on_match': false,
        'conditions': {},
        'actions': [
          {'kind': 'send_email', 'recipient': 'customer', 'answer_id': 'a-ops'},
        ],
        'created_at': '2026-11-16T09:00:00Z',
      },
    });
    await _pump(
      tester,
      http,
      Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showRuleEditor(c),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-action')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('action-kind-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send e-mail').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mail-template-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('mail-subject-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mail-template-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ops · Answer ops').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mail-subject-0')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('rule-name')), 'Notify');
    await tester.tap(find.byKey(const ValueKey('save-rule')));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/helpdesk/automation/rules'] as Map;
    final actions = body['actions'] as List;
    expect(actions.first['answer_id'], 'a-ops');
    expect(actions.first['subject'], isNull);
    expect(actions.first['body'], isNull);
  });

  testWidgets('editing an existing answer with teamId renders while teams load and preserves teamId on save', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/helpdesk/teams': (_) => [
        {'id': 'team1', 'name': 'R&D', 'active': true, 'members': [], 'created_at': '2026-11-01T09:00:00Z'},
      ],
      'GET /api/v1/prepared-answers/placeholders': (_) => <String>[],
      'PUT /api/v1/prepared-answers/a-fw': (_) => _answer('fw', teamId: 'team1'),
    });
    final existing = PreparedAnswer.fromJson(_answer('fw', teamId: 'team1'));
    await _pump(tester, http, Scaffold(body: AnswerEditor(answer: existing)));
    expect(find.text('R&D'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent = http.bodies['PUT /api/v1/prepared-answers/a-fw'] as Map;
    expect(sent['team_id'], 'team1');
  });
}
