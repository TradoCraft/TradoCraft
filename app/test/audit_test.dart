import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/admin_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/record_history.dart';

import 'fake_http.dart';

const _at = '2027-02-01T10:00:00Z';

String _shown(String iso) =>
    DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(iso).toLocal());

Map<String, Object?> _event(
  int id, {
  String action = 'updated',
  String entity = 'customer',
  String? name = 'Sam Sales',
  String? email = 'sam@example.com',
  Object? data = const <String, Object?>{},
}) => {
  'id': id,
  'occurred_at': _at,
  'user_id': name == null && email == null ? null : 'u1',
  'user_name': ?name,
  'user_email': ?email,
  'entity': entity,
  'entity_id': 'e$id',
  'action': action,
  'data': data,
};

Map<String, Object?> _page(List<Object?> items, {int? next}) => {
  'items': items,
  'next_before_id': ?next,
};

Future<void> _show(WidgetTester tester, FakeHttp http, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
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
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Map<String, dynamic>> _calls(FakeHttp http, String route) => [
  for (var i = 0; i < http.requests.length; i++)
    if (http.requests[i] == route) http.queries[i],
];

void main() {
  group('the audit trail in Administration', () {
    testWidgets('shows who changed which field from what to what', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/facets': (_) => {
          'entities': ['customer', 'supplier'],
        },
        'GET /api/v1/audit/events': (_) => _page([
          _event(
            3,
            data: {
              'changes': {
                'name': {'from': 'Acme', 'to': 'Acme NV'},
                'phone': {'from': null, 'to': '123'},
                'active': {'from': true, 'to': false},
              },
            },
          ),
          // A customer acting in the portal: no staff user, the actor is in the data.
          _event(
            2,
            action: 'portal_reply',
            entity: 'ticket',
            name: null,
            email: null,
            data: {'contact_id': 'c9'},
          ),
          // A save that changed nothing, and a user known by e-mail address only.
          _event(1, name: null, email: 'old@example.com'),
        ]),
      });
      // Only this permission: the page is the audit trail itself, with no tab switch.
      await _show(tester, http, const AdminPage());

      expect(find.text('updated'), findsNWidgets(2));
      expect(find.text('name: Acme → Acme NV'), findsOneWidget);
      expect(find.text('phone: – → 123'), findsOneWidget);
      expect(find.text('active: true → false'), findsOneWidget);
      expect(find.text('contact_id: c9'), findsOneWidget);
      expect(find.text('portal_reply'), findsOneWidget);
      expect(find.text('No details were recorded.'), findsOneWidget);
      // The kind of record is named in the company-wide trail.
      expect(find.text('·  ticket'), findsOneWidget);
      // Who and when: the name, the e-mail address, or "System".
      expect(find.text('Sam Sales  ·  ${_shown(_at)}'), findsOneWidget);
      expect(find.text('System  ·  ${_shown(_at)}'), findsOneWidget);
      expect(find.text('old@example.com  ·  ${_shown(_at)}'), findsOneWidget);
      // The first request asks for no filter at all.
      final q = _calls(http, 'GET /api/v1/audit/events').first;
      expect(q['entity'], isNull);
      expect(q['before_id'], isNull);
    });

    testWidgets('older events are loaded on request, and the button goes', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/facets': (_) => {'entities': <String>[]},
      });
      http.routes['GET /api/v1/audit/events'] = (_) {
        final before = http.queries.last['before_id'];
        return before == null
            ? _page([_event(3, action: 'newest'), _event(2)], next: 2)
            : _page([_event(1, action: 'oldest')]);
      };
      await _show(tester, http, const AdminPage());
      expect(find.text('newest'), findsOneWidget);
      expect(find.text('oldest'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('audit-more')));
      await tester.pumpAndSettle();
      expect(_calls(http, 'GET /api/v1/audit/events').last['before_id'], 2);
      expect(find.text('newest'), findsOneWidget);
      expect(find.text('oldest'), findsOneWidget);
      expect(find.byKey(const ValueKey('audit-more')), findsNothing);
    });

    testWidgets('older events keep the action the list was loaded with', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/facets': (_) => {'entities': <String>[]},
      });
      http.routes['GET /api/v1/audit/events'] = (_) {
        final before = http.queries.last['before_id'];
        return before == null
            ? _page([_event(3), _event(2)], next: 2)
            : _page([_event(1)]);
      };
      await _show(tester, http, const AdminPage());
      // Filter by action and confirm it.
      await tester.enterText(
        find.byKey(const ValueKey('audit-action')),
        'sent',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_calls(http, 'GET /api/v1/audit/events').last['action'], 'sent');
      // Edit the box without confirming, then ask for older events: still the confirmed action,
      // so that the cursor and the filter belong together.
      await tester.enterText(
        find.byKey(const ValueKey('audit-action')),
        'something else',
      );
      await tester.tap(find.byKey(const ValueKey('audit-more')));
      await tester.pumpAndSettle();
      final q = _calls(http, 'GET /api/v1/audit/events').last;
      expect(q['before_id'], 2);
      expect(q['action'], 'sent');
      // Confirming the new text starts over with it.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final fresh = _calls(http, 'GET /api/v1/audit/events').last;
      expect(fresh['action'], 'something else');
      expect(fresh['before_id'], isNull);
    });

    testWidgets('the company-wide trail names the record, not just its kind', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/facets': (_) => {'entities': <String>[]},
        'GET /api/v1/audit/events': (_) => _page([_event(7)]),
      });
      await _show(tester, http, const AdminPage());
      expect(find.text('e7'), findsOneWidget);
    });

    testWidgets('the filters go to the server and start the list over', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/facets': (_) => {
          'entities': ['customer', 'supplier'],
        },
        'GET /api/v1/audit/events': (_) => _page([_event(1)]),
      });
      await _show(tester, http, const AdminPage());

      // The kind of record, from what the trail has events for.
      await tester.tap(find.byKey(const ValueKey('audit-entity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('supplier').last);
      await tester.pumpAndSettle();
      expect(
        _calls(http, 'GET /api/v1/audit/events').last['entity'],
        'supplier',
      );

      // The action, when the user confirms it.
      await tester.enterText(
        find.byKey(const ValueKey('audit-action')),
        ' sent ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final q = _calls(http, 'GET /api/v1/audit/events').last;
      expect(q['action'], 'sent');
      expect(q['entity'], 'supplier', reason: 'filters add up');
      expect(
        q['before_id'],
        isNull,
        reason: 'a new filter starts at the newest',
      );

      // A period: picking a day sets `from`, clearing the dates removes it again.
      await tester.tap(find.byKey(const ValueKey('audit-from')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_calls(http, 'GET /api/v1/audit/events').last['from'], isNotNull);
      await tester.tap(find.byKey(const ValueKey('audit-clear-dates')));
      await tester.pumpAndSettle();
      expect(_calls(http, 'GET /api/v1/audit/events').last['from'], isNull);
    });

    testWidgets('an empty trail and a failing server say so', (tester) async {
      final empty = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/facets': (_) => {'entities': <String>[]},
        'GET /api/v1/audit/events': (_) => _page([]),
      });
      await _show(tester, empty, const AdminPage());
      expect(find.text('No events found.'), findsOneWidget);

      final failing = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/facets': (_) =>
            const FakeStatus(500, {'error': 'x', 'message': 'nope'}),
        'GET /api/v1/audit/events': (_) =>
            const FakeStatus(500, {'error': 'x', 'message': 'Database down'}),
      });
      await _show(tester, failing, const AdminPage());
      expect(find.text('Database down'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('is a tab only for those who may see the trail', (
      tester,
    ) async {
      Map<String, Object? Function(Object?)> routes(List<String> perms) => {
        'GET /api/v1/me': (_) => meJson(perms),
        'GET /api/v1/admin/users': (_) => <Object?>[],
        'GET /api/v1/admin/modules': (_) => <Object?>[],
        'GET /api/v1/admin/roles': (_) => <Object?>[],
        'GET /api/v1/audit/facets': (_) => {'entities': <String>[]},
        'GET /api/v1/audit/events': (_) => _page([_event(1, action: 'seen')]),
      };
      final without = FakeHttp(routes(['users.admin']));
      await _show(tester, without, const AdminPage());
      expect(find.text('Audit trail'), findsNothing);
      expect(without.requests, isNot(contains('GET /api/v1/audit/events')));

      final withIt = FakeHttp(routes(['users.admin', 'audit.view']));
      await _show(tester, withIt, const AdminPage());
      expect(find.text('Audit trail'), findsOneWidget);
      expect(withIt.requests, isNot(contains('GET /api/v1/audit/events')));
      await tester.tap(find.text('Audit trail'));
      await tester.pumpAndSettle();
      expect(find.text('seen'), findsOneWidget);
    });
  });

  group('the history of a record', () {
    testWidgets('opens from the History button and pages back', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
      });
      http.routes['GET /api/v1/audit/records/supplier/s1'] = (_) {
        final before = http.queries.last['before_id'];
        return before == null
            ? _page([
                _event(
                  3,
                  entity: 'supplier',
                  data: {
                    'changes': {
                      'payment_terms_days': {'from': 30, 'to': 45},
                    },
                  },
                ),
                _event(2, entity: 'supplier', action: 'sent'),
              ], next: 2)
            : _page([_event(1, entity: 'supplier', action: 'created')]);
      };
      await _show(
        tester,
        http,
        const Center(
          child: RecordHistoryButton(
            entity: 'supplier',
            id: 's1',
            title: 'Acme Motors',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('record-history')));
      await tester.pumpAndSettle();

      expect(find.text('History of Acme Motors'), findsOneWidget);
      expect(find.text('payment_terms_days: 30 → 45'), findsOneWidget);
      expect(find.text('sent'), findsOneWidget);
      // Within a record's own history the kind of record is not repeated.
      expect(find.text('·  supplier'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('history-more')));
      await tester.pumpAndSettle();
      expect(
        _calls(http, 'GET /api/v1/audit/records/supplier/s1').last['before_id'],
        2,
      );
      expect(find.text('created'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-more')), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('History of Acme Motors'), findsNothing);
    });

    testWidgets('shows what was recorded in full, however long', (
      tester,
    ) async {
      final long = List.generate(60, (i) => 'word$i').join(' ');
      expect(long.length, greaterThan(200));
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/records/customer/c1': (_) => _page([
          _event(1, data: {'notes': long}),
        ]),
      });
      await _show(
        tester,
        http,
        const RecordHistoryButton(entity: 'customer', id: 'c1', title: 'X'),
      );
      await tester.tap(find.byKey(const ValueKey('record-history')));
      await tester.pumpAndSettle();
      expect(find.text('notes: $long'), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
      // The record is not repeated in its own history.
      expect(find.text('e1'), findsNothing);
    });

    testWidgets('has no button without the right, and says when empty', (
      tester,
    ) async {
      final without = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['customers.read']),
      });
      await _show(
        tester,
        without,
        const RecordHistoryButton(entity: 'customer', id: 'c1', title: 'X'),
      );
      expect(find.byKey(const ValueKey('record-history')), findsNothing);

      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['audit.view']),
        'GET /api/v1/audit/records/customer/c1': (_) => _page([]),
      });
      await _show(
        tester,
        http,
        const RecordHistoryButton(entity: 'customer', id: 'c1', title: 'X'),
      );
      await tester.tap(find.byKey(const ValueKey('record-history')));
      await tester.pumpAndSettle();
      expect(find.text('No events found.'), findsOneWidget);
    });
  });
}
