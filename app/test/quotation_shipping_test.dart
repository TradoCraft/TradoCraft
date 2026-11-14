import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/format.dart';

import 'fake_http.dart';

Map<String, Object?> _line({
  String? productId = 'p1',
  String code = 'UNIT-100',
  String description = 'Process unit 100',
  String total = '3686.00',
}) => {
  'position': 1,
  'product_id': productId,
  'product_code': code,
  'description': description,
  'unit': 'pcs',
  'quantity': '1',
  'list_unit_price': '3880.0000',
  'line_discount_percent': '0',
  'pricing_type': productId == null ? 'net' : 'list',
  'rebate_percent': '5',
  'rebate_source': productId == null ? 'net' : 'general',
  'price_confirmed': true,
  'net_unit_price': '3686.0000',
  'line_total': total,
  'vat_rate': '21',
};

Map<String, Object?> _quotation(
  String status, {
  String shipping = 'not_required',
  String purpose = 'installation',
  String? country,
  bool shippingLine = false,
}) => {
  'id': 'q1',
  'company_id': 'co',
  'number': 'Q2026-00001',
  'revision': 1,
  'status': status,
  'customer_id': 'c2',
  'customer_name': 'Bêta Industrie SA',
  'customer_vat_number': null,
  'vat_regime': 'domestic',
  'customer_street': 'Rue 1',
  'customer_postal_code': '4000',
  'customer_city': 'Liège',
  'customer_country_code': 'BE',
  'customer_language': 'fr',
  'price_zone_code': 'Z2',
  'customer_discount_percent': '5',
  'currency': 'EUR',
  'quote_date': '2026-11-05',
  'purpose': purpose,
  'delivery_country_code': country,
  'shipping_status': shipping,
  'price_date': '2026-11-05',
  'valid_until': '2026-12-05',
  'notes': '',
  'subtotal': '3686.00',
  'vat_total': '774.06',
  'total': '4460.06',
  'created_by': 'u',
  'created_at': '2026-11-05T10:00:00Z',
  'updated_at': '2026-11-05T10:00:00Z',
  'lines': [
    _line(),
    if (shippingLine)
      _line(
        productId: null,
        code: 'SHIPPING',
        description: 'Shipping (Transco)',
        total: '250.00',
      ),
  ],
  'warnings': <Object?>[],
  'suggestions': <Object?>[],
  'vat_groups': [
    {'vat_rate': '21', 'base': '3686.00', 'vat': '774.06'},
  ],
};

Map<String, Object?> _product() => {
  'id': 'p1',
  'code': 'UNIT-100',
  'name': 'Process unit 100',
  'description': '',
  'unit': 'pcs',
  'product_type': 'manufactured',
  'tracking': 'none',
  'pricing_type': 'list',
  'vat_rate': '21',
  'active': true,
};

Map<String, Object?> _preview({bool shippingLine = false}) => {
  'price_zone_code': 'Z2',
  'customer_discount_percent': '5',
  'quote_date': '2026-11-05',
  'price_date': '2026-11-05',
  'unconfirmed_lines': 0,
  'warnings': <Object?>[],
  'suggestions': <Object?>[],
  // With a quoted shipping cost the server includes the SHIPPING line and its totals.
  'lines': [
    _line(),
    if (shippingLine)
      _line(
        productId: null,
        code: 'SHIPPING',
        description: 'Shipping (Transco)',
        total: '250.00',
      ),
  ],
  'vat_groups': [
    {
      'vat_rate': '21',
      'base': shippingLine ? '3936.00' : '3686.00',
      'vat': shippingLine ? '826.56' : '774.06',
    },
  ],
  'subtotal': shippingLine ? '3936.00' : '3686.00',
  'vat_total': shippingLine ? '826.56' : '774.06',
  'total': shippingLine ? '4762.56' : '4460.06',
};

FakeHttp _http(
  String status, {
  String shipping = 'not_required',
  String purpose = 'installation',
  String? country,
  bool shippingLine = false,
  List<String> perms = const ['quotations.read', 'quotations.write'],
  Map<String, Object? Function(Object?)> extra = const {},
}) {
  Object? q(Object? _) => _quotation(
    status,
    shipping: shipping,
    purpose: purpose,
    country: country,
    shippingLine: shippingLine,
  );
  return FakeHttp({
    'GET /api/v1/me': (_) => meJson(perms),
    'GET /api/v1/quotations/q1': q,
    'PUT /api/v1/quotations/q1': q,
    'GET /api/v1/customers/c2': (_) => {...customerJson(), 'id': 'c2'},
    'GET /api/v1/products/p1': (_) => _product(),
    'GET /api/v1/products': (_) => {
      'items': [_product()],
      'total': 1,
    },
    'POST /api/v1/quotations': q,
    'POST /api/v1/pricing/preview': (_) => _preview(shippingLine: shippingLine),
    ...extra,
  });
}

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The busy spinner of the screen keeps animating while the dialog is open, so settling never ends.
Future<void> _dialogUp(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets(
    'a draft shows purpose and country and sends them on save and preview',
    (tester) async {
      final http = _http('draft', purpose: 'installation', country: 'NL');
      await _pump(tester, http, const QuotationScreen(id: 'q1'));

      // Read back from the quotation; the customer's country is the hint when empty.
      final country = tester.widget<TextField>(
        find.byKey(const ValueKey('deliveryCountry')),
      );
      expect(country.controller!.text, 'NL');
      expect(find.text('Installation'), findsOneWidget);

      await tester.tap(find.text('Stock'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('deliveryCountry')),
        'fr',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      var preview = http.bodies['POST /api/v1/pricing/preview'] as Map;
      expect(preview['purpose'], 'stock');
      expect(preview['delivery_country_code'], 'FR');

      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      final put = http.bodies['PUT /api/v1/quotations/q1'] as Map;
      expect(put['purpose'], 'stock');
      expect(put['delivery_country_code'], 'FR');
      // The server re-adds the shipping line, so only product lines are sent.
      expect((put['lines'] as List).length, 1);
    },
  );

  testWidgets('a new quotation sends the purpose and defaults the country', (
    tester,
  ) async {
    final http = _http('draft');
    await _pump(tester, http, const QuotationScreen(customerId: 'c2'));
    expect(find.text('Default: BE'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextField, 'Add product'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Add product'),
      'unit',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('UNIT-100 · Process unit 100').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock'));
    await tester.pump();
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    final post = http.bodies['POST /api/v1/quotations'] as Map;
    expect(post['purpose'], 'stock');
    expect(post.containsKey('delivery_country_code'), isFalse);
  });

  testWidgets('a wrong country code is refused before saving', (tester) async {
    final http = _http('draft');
    await _pump(tester, http, const QuotationScreen(id: 'q1'));
    await tester.enterText(find.byKey(const ValueKey('deliveryCountry')), 'b');
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(find.textContaining('two-letter country code'), findsOneWidget);
    expect(http.requests, isNot(contains('PUT /api/v1/quotations/q1')));
  });

  testWidgets('a sent quotation shows purpose and country read-only', (
    tester,
  ) async {
    final http = _http('sent', purpose: 'stock', country: 'DE');
    await _pump(tester, http, const QuotationScreen(id: 'q1'));
    expect(find.byKey(const ValueKey('purpose')), findsNothing);
    expect(find.byKey(const ValueKey('deliveryCountry')), findsNothing);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('DE'), findsOneWidget);
  });

  testWidgets('a pending shipping quote shows the banner and the send error', (
    tester,
  ) async {
    final http = _http(
      'draft',
      shipping: 'pending',
      extra: {
        'POST /api/v1/quotations/q1/send': (_) => FakeStatus(409, {
          'error': 'conflict',
          'message': 'Shipping cost still to be quoted',
        }),
      },
    );
    await _pump(tester, http, const QuotationScreen(id: 'q1'));
    expect(find.byKey(const ValueKey('shipping-banner')), findsOneWidget);
    expect(find.textContaining('Waiting for a shipping quote'), findsOneWidget);

    await tester.tap(find.text('Mark as sent'));
    await tester.pumpAndSettle();
    expect(find.text('Shipping cost still to be quoted'), findsOneWidget);
    // Sales people cannot override.
    expect(find.text('Send anyway'), findsNothing);
  });

  testWidgets('no banner when no shipping quote is needed', (tester) async {
    await _pump(tester, _http('draft'), const QuotationScreen(id: 'q1'));
    expect(find.byKey(const ValueKey('shipping-banner')), findsNothing);
  });

  testWidgets('the quoted shipping line is shown read-only and not re-sent', (
    tester,
  ) async {
    final http = _http('draft', shipping: 'quoted', shippingLine: true);
    await _pump(tester, http, const QuotationScreen(id: 'q1'));
    expect(find.text('SHIPPING'), findsOneWidget);
    expect(find.text('Shipping (Transco)'), findsOneWidget);
    expect(find.textContaining('has been quoted'), findsOneWidget);
    // One editable row: the product line only (a single quantity field).
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    final put = http.bodies['PUT /api/v1/quotations/q1'] as Map;
    expect((put['lines'] as List).single['product_id'], 'p1');
  });

  testWidgets('the preview of an existing draft carries its id and shows the '
      'shipping line in the totals', (tester) async {
    final http = _http('draft', shipping: 'quoted', shippingLine: true);
    await _pump(tester, http, const QuotationScreen(id: 'q1'));
    final body = http.bodies['POST /api/v1/pricing/preview'] as Map;
    expect(body['quotation_id'], 'q1');
    // Totals come from the preview (product 3686.00 + shipping 250.00), not from client arithmetic.
    expect(find.text(money('3936.00')), findsOneWidget);
    expect(find.text(money('4762.56')), findsOneWidget);
    expect(find.text('SHIPPING'), findsOneWidget);
    expect(find.text(money('250.00')), findsWidgets);
  });

  testWidgets('without a shipping cost the preview has no shipping line', (
    tester,
  ) async {
    final http = _http('draft', shipping: 'pending');
    await _pump(tester, http, const QuotationScreen(id: 'q1'));
    expect(find.text('SHIPPING'), findsNothing);
    expect(find.text(money('4460.06')), findsOneWidget);
  });

  testWidgets('a new quotation previews without a quotation id', (
    tester,
  ) async {
    final http = _http('draft');
    await _pump(tester, http, const QuotationScreen(customerId: 'c2'));
    await tester.tap(find.widgetWithText(TextField, 'Add product'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Add product'),
      'unit',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('UNIT-100 · Process unit 100').last);
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/pricing/preview'] as Map;
    expect(body.containsKey('quotation_id'), isFalse);
  });

  group('send anyway', () {
    Map<String, Object? Function(Object?)> conflict({
      bool allowOverride = true,
    }) => {
      'POST /api/v1/quotations/q1/send': (_) => FakeStatus(409, {
        'error': 'conflict',
        'message': 'Shipping cost still to be quoted',
      }),
    };

    testWidgets('is offered with both permissions and sends the override', (
      tester,
    ) async {
      var overridden = false;
      final http = _http(
        'draft',
        shipping: 'pending',
        perms: const ['quotations.read', 'quotations.write', 'shipping.manage'],
        extra: {
          'POST /api/v1/quotations/q1/send': (_) => overridden
              ? _quotation('sent', shipping: 'pending')
              : FakeStatus(409, {
                  'error': 'conflict',
                  'message': 'Shipping cost still to be quoted',
                }),
        },
      );
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      await tester.tap(find.text('Mark as sent'));
      await _dialogUp(tester);
      expect(find.text('Send anyway'), findsWidgets);
      expect(
        find.textContaining('Shipping cost still to be quoted'),
        findsOneWidget,
      );

      overridden = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Send anyway'));
      await tester.pumpAndSettle();
      final i = http.requests.lastIndexOf('POST /api/v1/quotations/q1/send');
      expect(http.queries[i]['override_shipping'], true);
      expect(find.text('sent'), findsWidgets);
    });

    testWidgets('cancelling keeps the server message visible', (tester) async {
      final http = _http(
        'draft',
        shipping: 'pending',
        perms: const ['quotations.read', 'quotations.write', 'shipping.manage'],
        extra: conflict(),
      );
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      await tester.tap(find.text('Mark as sent'));
      await _dialogUp(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Shipping cost still to be quoted'), findsOneWidget);
      expect(
        http.requests.where((r) => r == 'POST /api/v1/quotations/q1/send'),
        hasLength(1),
      );
    });

    testWidgets('is not offered without quotations.write', (tester) async {
      final http = _http(
        'draft',
        shipping: 'pending',
        perms: const ['quotations.read', 'shipping.manage'],
        extra: conflict(),
      );
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      // Read-only users have no send button at all.
      expect(find.text('Mark as sent'), findsNothing);
      expect(find.text('Send anyway'), findsNothing);
    });
  });
}
