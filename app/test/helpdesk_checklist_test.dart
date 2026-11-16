import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_screen.dart';
import 'package:tradocraft_app/features/helpdesk/tickets_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

const _perms = ['helpdesk.read', 'helpdesk.write', 'helpdesk.reply'];

Map<String, Object?> _ticket({
  String id = 't1',
  String number = 'T2026-00007',
  String subject = 'Pump is noisy',
  int checklistTotal = 0,
  int checklistDone = 0,
}) => {
  'id': id,
  'number': number,
  'subject': subject,
  'status': 'open',
  'priority': 'normal',
  'category': 'service',
  'language': 'en',
  'customer_id': 'c1',
  'customer_name': 'Alpha NV',
  'contact_name': 'Anna',
  'contact_email': 'anna@alpha.example',
  'owner_user_id': 'u1',
  'owner_name': 'Support Agent',
  'team_id': 'team1',
  'team_name': 'Level 2',
  'internal': false,
  'article_count': 1,
  'created_at': '2026-11-09T09:00:00Z',
  'updated_at': '2026-11-09T09:00:00Z',
  ...ticketExtras(),
  'checklist_total': checklistTotal,
  'checklist_done': checklistDone,
};

Map<String, Object?> _item({
  required String id,
  required String description,
  required int position,
  bool done = false,
  String? doneByName,
  String? doneAt,
}) => {
  'id': id,
  'ticket_id': 't1',
  'description': description,
  'done': done,
  'position': position,
  'done_by': done ? 'u2' : null,
  'done_by_name': doneByName,
  'done_at': doneAt,
};

Map<String, Object?> _template({
  required String id,
  required String name,
  String? teamId,
  String? category,
}) => {
  'id': id,
  'name': name,
  'active': true,
  'team_id': teamId,
  'category': category,
  'items': [
    {'id': 'ti-$id', 'description': 'Step 1', 'position': 0},
  ],
  'created_at': '2026-11-01T09:00:00Z',
  'updated_at': '2026-11-01T09:00:00Z',
};

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1700, 1400);
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'ticket list shows checklist progress badge when total > 0 and hides when 0',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_perms),
        'GET /api/v1/helpdesk/teams': (_) => [],
        'GET /api/v1/helpdesk/tags': (_) => [],
        'GET /api/v1/tickets': (_) => {
          'items': [
            _ticket(
              id: 't1',
              number: 'T2026-00001',
              subject: 'Has checklist',
              checklistTotal: 5,
              checklistDone: 2,
            ),
            _ticket(
              id: 't2',
              number: 'T2026-00002',
              subject: 'No checklist',
              checklistTotal: 0,
              checklistDone: 0,
            ),
            _ticket(
              id: 't3',
              number: 'T2026-00003',
              subject: 'Done checklist',
              checklistTotal: 3,
              checklistDone: 3,
            ),
          ],
          'total': 3,
        },
      });

      await _pump(tester, http, const Scaffold(body: TicketsPage()));

      expect(find.byKey(const ValueKey('checklist-badge-t1')), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      expect(find.byKey(const ValueKey('checklist-badge-t2')), findsNothing);
      expect(find.byKey(const ValueKey('checklist-badge-t3')), findsOneWidget);
      expect(find.text('3/3'), findsOneWidget);

      final doneText = tester.widget<Text>(find.text('3/3'));
      expect(doneText.style?.color, Colors.green.shade800);
    },
  );

  testWidgets(
    'checklist card renders items, toggles done, adds item, and sorts matching templates first',
    (tester) async {
      final items = [
        _item(id: 'i1', description: 'Inspect motor', position: 0, done: false),
        _item(
          id: 'i2',
          description: 'Verify serial',
          position: 1,
          done: true,
          doneByName: 'Jo',
          doneAt: '2026-11-10T12:00:00Z',
        ),
      ];

      final http = FakeHttp({
        'GET /api/v1/helpdesk/tickets/t1/checklist': (_) => items,
        'GET /api/v1/helpdesk/checklist-templates': (_) => [
          _template(id: 'tpl-other', name: 'AAA General'),
          _template(
            id: 'tpl-cat',
            name: 'Service Checks',
            category: 'service',
          ),
          _template(
            id: 'tpl-both',
            name: 'Level 2 Service',
            teamId: 'team1',
            category: 'service',
          ),
        ],
        'PATCH /api/v1/helpdesk/tickets/t1/checklist/i1': (body) {
          final map = body as Map<String, dynamic>;
          return _item(
            id: 'i1',
            description: 'Inspect motor',
            position: 0,
            done: map['done'] as bool? ?? false,
            doneByName: 'Support Agent',
            doneAt: '2026-11-10T13:00:00Z',
          );
        },
        'POST /api/v1/helpdesk/tickets/t1/checklist': (body) {
          final map = body as Map<String, dynamic>;
          return _item(
            id: 'i3',
            description: map['description'] as String,
            position: 2,
          );
        },
      });

      await _pump(
        tester,
        http,
        const Scaffold(
          body: SingleChildScrollView(
            child: TicketChecklistCard(
              ticketId: 't1',
              teamId: 'team1',
              category: 'service',
            ),
          ),
        ),
      );

      expect(find.text('Checklist'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Inspect motor'), findsOneWidget);
      expect(find.text('Verify serial'), findsOneWidget);
      expect(find.textContaining('Jo'), findsOneWidget);

      // Toggle first item done.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(http.bodies['PATCH /api/v1/helpdesk/tickets/t1/checklist/i1'], {
        'done': true,
      });
      expect(find.text('2/2'), findsOneWidget);

      // Add a new item.
      await tester.enterText(
        find.byKey(const ValueKey('checklist-add-input')),
        'Check seal',
      );
      await tester.tap(find.byKey(const ValueKey('checklist-add-button')));
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/helpdesk/tickets/t1/checklist'], {
        'description': 'Check seal',
      });
      expect(find.text('Check seal'), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);

      // Open apply-template menu and verify matching templates appear before general ones.
      await tester.tap(find.byKey(const ValueKey('checklist-apply-template')));
      await tester.pumpAndSettle();

      final yBoth = tester.getTopLeft(find.text('Level 2 Service')).dy;
      final yCat = tester.getTopLeft(find.text('Service Checks')).dy;
      final yOther = tester.getTopLeft(find.text('AAA General')).dy;
      expect(yBoth, lessThan(yCat));
      expect(yCat, lessThan(yOther));
    },
  );
}
