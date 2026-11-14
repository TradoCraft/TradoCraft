import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/customers/closures_dialog.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _closure({
  String id = 'cl1',
  String from = '2099-12-24',
  String to = '2100-01-02',
  String kind = 'collective_leave',
  String notes = 'Christmas break',
}) => {
  'id': id,
  'customer_id': 'c2',
  'customer_code': 'C0002',
  'customer_name': 'Bêta Industrie SA',
  'starts_on': from,
  'ends_on': to,
  'kind': kind,
  'notes': notes,
  'source': 'staff',
  'created_at': '2026-11-09T10:00:00Z',
};

Future<void> _pump(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ClosuresDialog(customer: Customer.fromJson(customerJson())),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a reader sees the closures but cannot change them', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['customers.read']),
      'GET /api/v1/customers/c2/closures': (_) => [
        _closure(),
        _closure(
          id: 'cl2',
          from: '2099-06-01',
          to: '2099-06-01',
          kind: 'works',
          notes: 'Roof repair',
        ),
      ],
    });
    await _pump(tester, http);

    expect(find.textContaining('24/12/2099 – 02/01/2100'), findsOneWidget);
    expect(find.textContaining('Collective leave'), findsOneWidget);
    expect(find.text('Christmas break'), findsOneWidget);
    // A one-day closure shows a single date.
    expect(find.textContaining('01/06/2099 · Works'), findsOneWidget);
    expect(find.text('Add closure'), findsNothing);
    expect(find.byTooltip('Remove'), findsNothing);
  });

  testWidgets('a secretary adds a closure and removes another', (tester) async {
    var closures = [_closure()];
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['customers.read', 'closures.write']),
      'GET /api/v1/customers/c2/closures': (_) => closures,
      'POST /api/v1/customers/c2/closures': (body) {
        final b = body! as Map;
        closures = [
          ...closures,
          _closure(
            id: 'new',
            from: (b['starts_on'] as String).substring(0, 10),
            to: (b['ends_on'] as String).substring(0, 10),
            kind: b['kind'] as String,
            notes: b['notes'] as String,
          ),
        ];
        return closures.last;
      },
      'DELETE /api/v1/customers/c2/closures/cl1': (_) {
        closures = closures.where((c) => c['id'] != 'cl1').toList();
        return null;
      },
    });
    await _pump(tester, http);

    await tester.tap(find.text('Add closure'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Stocktaking');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final sent = http.bodies['POST /api/v1/customers/c2/closures']! as Map;
    expect(sent['kind'], 'holiday');
    expect(sent['notes'], 'Stocktaking');
    expect(sent['starts_on'], sent['ends_on'], reason: 'one day by default');
    expect(find.text('Stocktaking'), findsOneWidget);

    // Removing asks first, showing what is removed; cancelling deletes nothing.
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Christmas break'), findsNWidgets(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      http.requests,
      isNot(contains('DELETE /api/v1/customers/c2/closures/cl1')),
    );

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('DELETE /api/v1/customers/c2/closures/cl1'));
    expect(find.text('Christmas break'), findsNothing);
  });

  testWidgets('a failed load can be retried', (tester) async {
    var attempt = 0;
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['customers.read']),
      'GET /api/v1/customers/c2/closures': (_) => ++attempt == 1
          ? const FakeStatus(500, {'error': 'internal', 'message': 'boom'})
          : [_closure()],
    });
    await _pump(tester, http);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Christmas break'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Christmas break'), findsOneWidget);
  });

  testWidgets('a refused closure shows the reason and stays open', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['customers.read', 'closures.write']),
      'GET /api/v1/customers/c2/closures': (_) => <Object?>[],
      'POST /api/v1/customers/c2/closures': (_) => const FakeStatus(422, {
        'error': 'validation',
        'message': 'ends_on is before starts_on',
      }),
    });
    await _pump(tester, http);
    expect(find.text('No closures recorded.'), findsOneWidget);

    await tester.tap(find.text('Add closure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ends_on is before starts_on'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget, reason: 'the form stays open');
  });

  testWidgets('past closures are only fetched when asked for', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['customers.read']),
      'GET /api/v1/customers/c2/closures': (_) => <Object?>[],
    });
    await _pump(tester, http);
    expect(http.queries.where((q) => q.containsKey('from')), isEmpty);

    await tester.tap(find.text('Show past closures'));
    await tester.pumpAndSettle();
    expect(http.queries.last['from'].toString(), startsWith('1900-01-01'));

    // Switching it off asks for what has not ended again, without `from`.
    await tester.tap(find.text('Show past closures'));
    await tester.pumpAndSettle();
    final list = [
      for (var i = 0; i < http.requests.length; i++)
        if (http.requests[i] == 'GET /api/v1/customers/c2/closures')
          http.queries[i],
    ];
    expect(list.length, 3);
    expect(list.last.containsKey('from'), isFalse);
  });
}
