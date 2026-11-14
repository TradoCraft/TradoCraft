import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/opportunities/opportunity_form.dart';
import 'package:tradocraft_app/features/opportunities/opportunity_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _opp({String? grid}) => {
  'id': 'o1',
  'number': 'OPP-1',
  'title': 'Tower',
  'customer_id': 'c2',
  'customer_name': 'Bêta Industrie SA',
  'owner_user_id': 'u1',
  'owner_name': 'Owner',
  'stage': 'lead',
  'expected_value': '1000',
  'probability': 10,
  'notes': '',
  'power_grid_id': grid,
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _grid(String id, int voltage) => {
  'id': id,
  'country_code': 'BE',
  'name': 'BE $voltage',
  'voltage_v': voltage,
  'phases': voltage > 300 ? 3 : 1,
  'frequency_hz': 50,
  'active': true,
};

FakeHttp _http({String? grid, Object? Function(Object?)? onPut}) => FakeHttp({
  'GET /api/v1/me': (_) =>
      meJson(['opportunities.read', 'opportunities.write']),
  'GET /api/v1/opportunities/o1': (_) => _opp(grid: grid),
  'PUT /api/v1/opportunities/o1': onPut ?? (_) => _opp(grid: grid),
  'GET /api/v1/customers/c2': (_) => customerJson(),
  'GET /api/v1/power-grids': (_) => [_grid('g1', 230), _grid('g2', 400)],
  'GET /api/v1/opportunities/o1/baseline': (_) => [],
  'GET /api/v1/baseline-item-types': (_) => [],
  'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
});

Future<void> _pump(WidgetTester tester, FakeHttp h, Widget home) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(h))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(meProvider);
            return home;
          },
        ),
      ),
    ),
  );
  // The grids depend on the country of the customer: two requests in a row.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}

Widget _form(String? grid) => Scaffold(
  body: OpportunityForm(opportunity: Opportunity.fromJson(_opp(grid: grid))),
);

void main() {
  testWidgets('the screen shows the grid and the site baseline section', (
    tester,
  ) async {
    await _pump(tester, _http(grid: 'g2'), const OpportunityScreen(id: 'o1'));
    expect(find.text('Power grid'), findsOneWidget);
    expect(find.text('400 V 3ph 50 Hz'), findsOneWidget);
    expect(find.text('Site baseline'), findsOneWidget);
    expect(find.byKey(const ValueKey('baseline-empty')), findsOneWidget);
  });

  testWidgets('the screen omits the grid when none is set', (tester) async {
    await _pump(tester, _http(), const OpportunityScreen(id: 'o1'));
    expect(find.text('Power grid'), findsNothing);
  });

  testWidgets('the form offers the grids of the customer country', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h, _form(null));
    expect(find.byKey(const ValueKey('grid-BE-2')), findsOneWidget);
    final i = h.requests.indexOf('GET /api/v1/power-grids');
    expect(h.queries[i]['country'], 'BE');
  });

  testWidgets('a chosen grid is sent as power_grid_id', (tester) async {
    final h = _http();
    await _pump(tester, h, _form(null));
    await tester.tap(find.byKey(const ValueKey('grid-BE-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('400 V 3ph 50 Hz').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = h.bodies['PUT /api/v1/opportunities/o1'] as Map;
    expect(body['power_grid_id'], 'g2');
    expect(body.containsKey('clear_power_grid'), isFalse);
  });

  testWidgets('clearing a stored grid sends clear_power_grid', (tester) async {
    final h = _http(grid: 'g2');
    await _pump(tester, h, _form('g2'));
    await tester.tap(find.byKey(const ValueKey('grid-BE-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any grid in this country').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = h.bodies['PUT /api/v1/opportunities/o1'] as Map;
    expect(body['clear_power_grid'], true);
    expect(body.containsKey('power_grid_id'), isFalse);
  });

  testWidgets('a refusal about the customer country is shown', (tester) async {
    final h = _http(
      onPut: (_) => const FakeStatus(422, {
        'error': 'validation',
        'message': 'power grid does not belong to the customer country',
      }),
    );
    await _pump(tester, h, _form(null));
    await tester.tap(find.byKey(const ValueKey('grid-BE-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('230 V 1ph 50 Hz').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('customer country'), findsOneWidget);
  });
}
