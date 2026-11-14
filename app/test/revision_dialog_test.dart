import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _comparison({
  Object? requote = false,
  Object? oldShipping = '0',
}) => {
  'old_price_date': '2025-06-01',
  'new_price_date': '2026-11-05',
  'old_subtotal': '3538.56',
  'old_shipping_total': ?oldShipping,
  'shipping_requote_needed': ?requote,
  'new_subtotal': '3686.00',
  'difference': '147.44',
  'lines': [
    {
      'position': 1,
      'product_code': 'UNIT-100',
      'description': 'Process unit 100',
      'quantity': '1',
      'pricing_type': 'list',
      'old_list_unit_price': '3724.80',
      'new_list_unit_price': '3880.00',
      'old_rebate_percent': '5',
      'new_rebate_percent': '5',
      'old_line_total': '3538.56',
      'new_line_total': '3686.00',
      'difference': '147.44',
      'needs_confirmation': false,
    },
  ],
};

Map<String, Object?> _shippingLine() => {
  'position': 2,
  'product_code': 'SHIPPING',
  'description': 'Shipping (Transco)',
  'quantity': '1',
  'unit': 'pc',
  'pricing_type': 'net',
  'list_unit_price': '250.00',
  'net_unit_price': '250.00',
  'rebate_percent': '0',
  'rebate_source': 'none',
  'line_discount_percent': '0',
  'line_total': '250.00',
  'vat_rate': '21',
  'price_confirmed': true,
};

Quotation _quotation({bool shipping = false}) => Quotation.fromJson({
  'id': 'q1',
  'company_id': 'co',
  'number': 'Q2026-00007',
  'revision': 1,
  'status': 'sent',
  'customer_id': 'c1',
  'customer_name': 'Alpha',
  'vat_regime': 'domestic',
  'customer_street': '',
  'customer_postal_code': '',
  'customer_city': '',
  'customer_country_code': 'BE',
  'customer_language': 'nl',
  'price_zone_code': 'Z2',
  'customer_discount_percent': '5',
  'currency': 'EUR',
  'quote_date': '2026-11-01',
  'purpose': 'installation',
  'shipping_status': 'not_required',
  'price_date': '2025-06-01',
  'valid_until': '2026-12-01',
  'notes': '',
  'subtotal': '3538.56',
  'vat_total': '743.10',
  'total': '4281.66',
  'created_by': 'u',
  'created_at': '2026-11-01T10:00:00Z',
  'updated_at': '2026-11-01T10:00:00Z',
  'lines': [if (shipping) _shippingLine()],
  'warnings': <Object?>[],
  'suggestions': <Object?>[],
  'vat_groups': [],
});

Future<void> _open(
  WidgetTester tester,
  Object? Function(Object?) repricing, {
  bool shipping = false,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = fakeDio(
    FakeHttp({'GET /api/v1/quotations/q1/repricing': repricing}),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<RevisionPricing>(
              context: context,
              builder: (_) =>
                  RevisionDialog(quotation: _quotation(shipping: shipping)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

final _reset = find.byKey(const ValueKey('revision-shipping-reset'));
final _kept = find.byKey(const ValueKey('revision-shipping-kept'));

void main() {
  testWidgets('shows agreed versus current prices and returns the choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dio = fakeDio(
      FakeHttp({'GET /api/v1/quotations/q1/repricing': (_) => _comparison()}),
    );
    RevisionPricing? choice;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => choice = await showDialog<RevisionPricing>(
                context: context,
                builder: (_) => RevisionDialog(quotation: _quotation()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('price list of 01/06/2025'), findsOneWidget);
    expect(find.text('€ 3.538,56'), findsOneWidget);
    expect(find.text('€ 3.686,00'), findsOneWidget);
    expect(find.textContaining('(€ 147,44)'), findsOneWidget);

    await tester.tap(find.text('Keep agreed prices'));
    await tester.pumpAndSettle();
    expect(choice, RevisionPricing.keep);
  });

  testWidgets('shows the existing shipping charge and the reset warning', (
    tester,
  ) async {
    await _open(
      tester,
      (_) => _comparison(requote: true, oldShipping: '250.00'),
      shipping: true,
    );
    expect(_reset, findsOneWidget);
    expect(find.text('Existing shipping charge: € 250,00'), findsOneWidget);
    expect(find.textContaining('will be reset'), findsOneWidget);
    expect(
      find.textContaining('new shipping quote from logistics'),
      findsOneWidget,
    );
  });

  testWidgets('keeps the shipping disclosure when the comparison fails', (
    tester,
  ) async {
    await _open(
      tester,
      (_) => const FakeStatus(500, {'error': 'internal', 'message': 'boom'}),
      shipping: true,
    );
    expect(find.textContaining('could not be calculated'), findsWidgets);
    expect(_reset, findsOneWidget);
    expect(find.text('Existing shipping charge: € 250,00'), findsOneWidget);
    expect(find.textContaining('will be reset'), findsOneWidget);
  });

  testWidgets('an older server without the flag falls back to the quotation', (
    tester,
  ) async {
    await _open(
      tester,
      (_) => _comparison(requote: null, oldShipping: null),
      shipping: true,
    );
    expect(_reset, findsOneWidget);
    expect(find.text('Existing shipping charge: € 250,00'), findsOneWidget);
  });

  testWidgets('no warning without shipping when the flag is false', (
    tester,
  ) async {
    await _open(tester, (_) => _comparison());
    expect(_reset, findsNothing);
    expect(_kept, findsNothing);
    expect(find.textContaining('will be reset'), findsNothing);
    // Older server and no shipping: still nothing to warn about.
    await _open(tester, (_) => _comparison(requote: null, oldShipping: null));
    expect(_reset, findsNothing);
  });

  testWidgets('labels the subtotals as product-only', (tester) async {
    await _open(tester, (_) => _comparison());
    expect(
      find.textContaining('Products excl. shipping and VAT: € 3.538,56'),
      findsOneWidget,
    );
    expect(find.textContaining('Total excl. VAT'), findsNothing);
  });

  testWidgets('notes that keep carries shipping over only when there is any', (
    tester,
  ) async {
    await _open(tester, (_) => _comparison(), shipping: true);
    expect(_kept, findsOneWidget);
    expect(find.textContaining('carried over'), findsOneWidget);
    expect(find.textContaining('€ 250,00)'), findsOneWidget);
  });
}
