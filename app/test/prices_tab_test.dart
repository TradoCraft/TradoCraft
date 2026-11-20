import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/products/prices_tab.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

final _product = {
  'id': 'p1',
  'code': 'PUMP-05',
  'name': 'Pump',
  'description': '',
  'unit': 'pcs',
  'product_type': 'purchased',
  'tracking': 'none',
  ...pricingFlags('list'),
  'vat_rate': '21',
  'active': true,
};

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, Object?> _price(String id, String price, DateTime from) => {
  'id': id,
  'zone_id': 'z2',
  'zone_code': 'Z2',
  'unit_price': price,
  'valid_from': _day(from),
};

Future<void> _pump(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1400, 2000);
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
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(meProvider);
              return PricesTab(product: Product.fromJson(_product));
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('only prices starting after today are planned', () {
    final now = DateTime.utc(2026, 11, 19, 0, 30);
    ZonePriceEntry entry(DateTime from) =>
        ZonePriceEntry.fromJson(_price('x', '1', from));
    expect(isPlanned(entry(DateTime(2026, 11, 20)), now: now), isTrue);
    expect(isPlanned(entry(DateTime(2026, 11, 19)), now: now), isFalse);
    expect(isPlanned(entry(DateTime(2026, 1, 1)), now: now), isFalse);
    expect(isPlanned(entry(DateTime(2026, 11, 19)), now: now.toLocal()), isFalse);
  });

  testWidgets('a planned price can be corrected or deleted, a price in effect cannot', (
    tester,
  ) async {
    final today = DateTime.now();
    final planned = DateTime(today.year, today.month, today.day + 30);
    final prices = [
      _price('pr-planned', '5320.0000', planned),
      _price('pr-current', '512.0000', DateTime(2026, 1, 1)),
    ];
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['prices.write']),
      'GET /api/v1/price-zones': (_) => [
        {'id': 'z2', 'code': 'Z2', 'name': 'Dealer', 'sort_order': 2},
      ],
      'GET /api/v1/products/p1/prices': (_) => prices,
      'PUT /api/v1/products/p1/prices/pr-planned': (b) {
        final m = b! as Map;
        prices[0] = _price(
          'pr-planned',
          m['unit_price'] as String,
          DateTime.parse(m['valid_from'] as String),
        );
        return prices[0];
      },
      'DELETE /api/v1/products/p1/prices/pr-planned': (_) {
        prices.removeAt(0);
        return null;
      },
    });
    await _pump(tester, http);

    // Only the planned price offers the correction.
    expect(find.byKey(const ValueKey('price-correct-pr-planned')), findsOneWidget);
    expect(find.byKey(const ValueKey('price-correct-pr-current')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('price-correct-pr-planned')));
    await tester.pumpAndSettle();
    expect(find.text('Correct planned price'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '532');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(http.bodies['PUT /api/v1/products/p1/prices/pr-planned'], {
      'unit_price': '532',
      // The dialog keeps the planned date; the client sends dates as ISO date-times.
      'valid_from': planned.toIso8601String(),
    });

    await tester.tap(find.byKey(const ValueKey('price-correct-pr-planned')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('price-delete')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('DELETE /api/v1/products/p1/prices/pr-planned'));
    expect(find.byKey(const ValueKey('price-correct-pr-planned')), findsNothing);
  });

  testWidgets('saving a correction without editing the price sends the existing price', (
    tester,
  ) async {
    final today = DateTime.now();
    final planned = DateTime(today.year, today.month, today.day + 30);
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['prices.write']),
      'GET /api/v1/price-zones': (_) => [
        {'id': 'z2', 'code': 'Z2', 'name': 'Dealer', 'sort_order': 2},
      ],
      'GET /api/v1/products/p1/prices': (_) => [
        _price('pr-planned', '5320.5000', planned),
      ],
      'PUT /api/v1/products/p1/prices/pr-planned': (_) =>
          _price('pr-planned', '5320.5', planned),
    });
    await _pump(tester, http);

    await tester.tap(find.byKey(const ValueKey('price-correct-pr-planned')));
    await tester.pumpAndSettle();
    // The field is prefilled from the existing price: decimal comma, no trailing zeros.
    expect(find.widgetWithText(TextField, '5320,5'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (http.bodies['PUT /api/v1/products/p1/prices/pr-planned']! as Map)['unit_price'],
      '5320.5',
    );
  });

  testWidgets('without prices.write nothing can be corrected', (tester) async {
    final today = DateTime.now();
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(const []),
      'GET /api/v1/price-zones': (_) => const [],
      'GET /api/v1/products/p1/prices': (_) => [
        _price(
          'pr-planned',
          '5320.0000',
          DateTime(today.year, today.month, today.day + 30),
        ),
      ],
    });
    await _pump(tester, http);
    expect(find.byKey(const ValueKey('price-correct-pr-planned')), findsNothing);
  });
}
