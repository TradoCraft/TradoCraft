import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/sales_hints.dart';

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
  String? gridId,
  List<Object?>? warnings,
  List<Object?>? suggestions,
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
  'power_grid_id': gridId,
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
  'warnings': warnings ?? <Object?>[],
  'suggestions': suggestions ?? <Object?>[],
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

Map<String, Object?> _preview({
  List<Object?>? warnings,
  List<Object?>? suggestions,
  int lines = 1,
}) => {
  'price_zone_code': 'Z2',
  'customer_discount_percent': '5',
  'quote_date': '2026-11-05',
  'price_date': '2026-11-05',
  'unconfirmed_lines': 0,
  'warnings': warnings ?? <Object?>[],
  'suggestions': suggestions ?? <Object?>[],
  'lines': [for (var i = 0; i < lines; i++) _line()],
  'vat_groups': [
    {'vat_rate': '21', 'base': '3686.00', 'vat': '774.06'},
  ],
  'subtotal': '3686.00',
  'vat_total': '774.06',
  'total': '4460.06',
};

Map<String, Object?> _grid(String id, int voltage, {bool active = true}) => {
  'id': id,
  'country_code': 'NL',
  'name': 'NL $voltage',
  'voltage_v': voltage,
  'phases': voltage > 300 ? 3 : 1,
  'frequency_hz': 50,
  'active': active,
};

Map<String, Object?> _warning(String status) => {
  'kind': 'power_grid',
  'product_code': 'UNIT-100',
  'message': 'server text',
  'details': {
    'status': status,
    'country_code': 'NL',
    'supported': [
      {
        'id': 's',
        'current_type': 'ac',
        'voltage_v': 110,
        'phases': 1,
        'frequency_hz': 60,
        'tolerance_pct': 10,
      },
    ],
    'available': [_grid('g1', 230)],
  },
};

final _pair = {
  'kind': 'incompatible_products',
  'product_code': 'UNIT-100',
  'message': 'server text',
  'details': {
    'product_codes': ['UNIT-100', 'HOSE-9'],
    'note': 'Wrong thread',
    'relation_id': 'r1',
  },
};

Map<String, Object?> _suggestion({
  String id = 'p2',
  String reason = 'rule',
  int? strength = 80,
  double? confidence,
}) => {
  'product_id': id,
  'product_code': 'CTRL-2',
  'product_name': 'Controller 2',
  'reason': reason,
  'because_of_code': 'UNIT-100',
  'note': '',
  'strength': ?strength,
  'confidence': ?confidence,
};

FakeHttp _http(
  String status, {
  String purpose = 'installation',
  String country = 'NL',
  String? gridId,
  List<Object?> grids = const [],
  List<Object?>? warnings,
  List<Object?>? suggestions,
  bool previewHints = true,
  Map<String, Object? Function(Object?)> extra = const {},
}) {
  Object? q(Object? _) => _quotation(
    status,
    purpose: purpose,
    country: country,
    gridId: gridId,
    warnings: previewHints ? null : warnings,
    suggestions: previewHints ? null : suggestions,
  );
  var previews = 0;
  return FakeHttp({
    'GET /api/v1/me': (_) => meJson(['quotations.read', 'quotations.write']),
    'GET /api/v1/quotations/q1': q,
    'PUT /api/v1/quotations/q1': q,
    'GET /api/v1/customers/c2': (_) => {...customerJson(), 'id': 'c2'},
    'GET /api/v1/products/p1': (_) => _product(),
    'GET /api/v1/products/p2': (_) => {
      ..._product(),
      'id': 'p2',
      'code': 'CTRL-2',
      'name': 'Controller 2',
    },
    'GET /api/v1/power-grids': (_) => grids,
    'POST /api/v1/pricing/preview': (_) {
      previews++;
      // Once the suggestion has been added the server stops suggesting it.
      return _preview(
        warnings: warnings,
        suggestions: previews == 1 ? suggestions : const [],
        lines: previews,
      );
    },
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

void main() {
  group('warnings widget', () {
    Future<void> show(
      WidgetTester tester,
      List<SalesWarning> w, [
      List<SalesSuggestion> s = const [],
      void Function(SalesSuggestion)? onAdd,
    ]) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SalesHints(warnings: w, suggestions: s, onAdd: onAdd),
          ),
        ),
      ),
    );

    SalesWarning warning(Map<String, Object?> j) => SalesWarning.fromJson(j);

    testWidgets('nothing at all renders nothing', (tester) async {
      await show(tester, const []);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('incompatible grid shows supported and available', (
      tester,
    ) async {
      await show(tester, [warning(_warning('incompatible'))]);
      expect(find.text('Power grid'), findsOneWidget);
      expect(
        find.text('UNIT-100 does not fit the power grid at the delivery site.'),
        findsOneWidget,
      );
      expect(find.text('Supported: AC 110 V 1ph 60 Hz ±10 %'), findsOneWidget);
      expect(find.text('Available: 230 V 1ph 50 Hz'), findsOneWidget);
    });

    testWidgets('needs external supply is informational', (tester) async {
      await show(tester, [warning(_warning('needs_external_supply'))]);
      expect(
        find.text('UNIT-100 runs on DC and needs an external power supply.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.info_outlined), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    });

    testWidgets('unknown grid hints at adding the grid data', (tester) async {
      await show(tester, [warning(_warning('unknown_grid'))]);
      expect(find.textContaining('No grid data for NL'), findsOneWidget);
      expect(find.textContaining('Add the country'), findsOneWidget);
    });

    testWidgets('incompatible products show the pair and the note', (
      tester,
    ) async {
      await show(tester, [warning(_pair), warning(_warning('incompatible'))]);
      expect(find.text('Incompatible products'), findsOneWidget);
      expect(
        find.text('UNIT-100 and HOSE-9 are not compatible.'),
        findsOneWidget,
      );
      expect(find.text('Wrong thread'), findsOneWidget);
      // Grouped: one heading per kind.
      expect(find.text('Power grid'), findsOneWidget);
    });

    testWidgets('an unknown status falls back to the server message', (
      tester,
    ) async {
      await show(tester, [warning(_warning('something_new'))]);
      expect(find.text('server text'), findsOneWidget);
    });

    testWidgets('suggestions show the reason, strength and confidence', (
      tester,
    ) async {
      SalesSuggestion? added;
      await show(tester, const [], [
        SalesSuggestion.fromJson(_suggestion()),
        SalesSuggestion.fromJson(
          _suggestion(
            id: 'p3',
            reason: 'often_bought_together',
            strength: null,
            confidence: 0.4,
          ),
        ),
      ], (s) => added = s);
      expect(find.text('Suggested additions (2)'), findsOneWidget);
      expect(find.text('Rule'), findsOneWidget);
      expect(find.text('Often bought together'), findsOneWidget);
      expect(find.text('Strength 80'), findsOneWidget);
      expect(find.text('Confidence 40 %'), findsOneWidget);
      await tester.tap(find.text('Add').first);
      expect(added?.productId, 'p2');
    });

    testWidgets('without onAdd there is no Add button', (tester) async {
      await show(tester, const [], [SalesSuggestion.fromJson(_suggestion())]);
      expect(find.text('Add'), findsNothing);
      expect(find.text('CTRL-2 · Controller 2'), findsOneWidget);
    });
  });

  group('quotation editor', () {
    testWidgets('shows the preview warnings and suggestions', (tester) async {
      final http = _http(
        'draft',
        warnings: [_warning('incompatible'), _pair],
        suggestions: [_suggestion()],
      );
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      expect(
        find.text('UNIT-100 does not fit the power grid at the delivery site.'),
        findsOneWidget,
      );
      expect(
        find.text('UNIT-100 and HOSE-9 are not compatible.'),
        findsOneWidget,
      );
      expect(find.text('CTRL-2 · Controller 2'), findsOneWidget);
    });

    testWidgets('Add appends a quantity-1 line and removes the suggestion', (
      tester,
    ) async {
      final http = _http('draft', suggestions: [_suggestion()]);
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('CTRL-2 · Controller 2'), findsNothing);
      expect(find.text('CTRL-2'), findsOneWidget);
      final preview = http.bodies['POST /api/v1/pricing/preview'] as Map;
      final lines = preview['lines'] as List;
      expect(lines, hasLength(2));
      expect(lines.last['product_id'], 'p2');
      expect(lines.last['quantity'].toString(), anyOf('1', '1.0'));
      // A suggestion for a product already on the quotation is not offered.
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(
        (http.bodies['PUT /api/v1/quotations/q1'] as Map)['lines'],
        hasLength(2),
      );
    });

    testWidgets('a stock quotation shows no hints', (tester) async {
      final http = _http(
        'draft',
        purpose: 'stock',
        warnings: [_warning('incompatible')],
        suggestions: [_suggestion()],
      );
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      expect(find.byKey(const ValueKey('sales-hints')), findsNothing);
      expect(find.byKey(const ValueKey('suggestions-panel')), findsNothing);
    });

    testWidgets('a sent quotation shows nothing from a plain GET', (
      tester,
    ) async {
      await _pump(tester, _http('sent'), const QuotationScreen(id: 'q1'));
      expect(find.byKey(const ValueKey('sales-hints')), findsNothing);
    });

    testWidgets('a sent quotation shows warnings that came back', (
      tester,
    ) async {
      await _pump(
        tester,
        _http(
          'sent',
          previewHints: false,
          warnings: [_warning('incompatible')],
        ),
        const QuotationScreen(id: 'q1'),
      );
      expect(find.byKey(const ValueKey('sales-hints')), findsOneWidget);
    });

    group('power grid dropdown', () {
      testWidgets('is hidden with fewer than two active grids', (tester) async {
        await _pump(
          tester,
          _http(
            'draft',
            grids: [_grid('g1', 230), _grid('g2', 400, active: false)],
          ),
          const QuotationScreen(id: 'q1'),
        );
        expect(find.text('Power grid'), findsNothing);
      });

      testWidgets('appears with several grids and its id is sent', (
        tester,
      ) async {
        final http = _http(
          'draft',
          grids: [_grid('g1', 230), _grid('g2', 400)],
        );
        await _pump(tester, http, const QuotationScreen(id: 'q1'));
        expect(find.text('Power grid'), findsOneWidget);
        expect(find.text('Any grid in this country'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('grid-NL-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('400 V 3ph 50 Hz').last);
        await tester.pumpAndSettle();
        expect(
          (http.bodies['POST /api/v1/pricing/preview'] as Map)['power_grid_id'],
          'g2',
        );
        await tester.tap(find.text('Save draft'));
        await tester.pumpAndSettle();
        expect(
          (http.bodies['PUT /api/v1/quotations/q1'] as Map)['power_grid_id'],
          'g2',
        );
      });

      testWidgets('a grid with none stored sends its id and no clear flag', (
        tester,
      ) async {
        final http = _http(
          'draft',
          grids: [_grid('g1', 230), _grid('g2', 400)],
        );
        await _pump(tester, http, const QuotationScreen(id: 'q1'));
        await tester.tap(find.byKey(const ValueKey('grid-NL-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('230 V 1ph 50 Hz').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save draft'));
        await tester.pumpAndSettle();
        final put = http.bodies['PUT /api/v1/quotations/q1'] as Map;
        expect(put['power_grid_id'], 'g1');
        expect(put.containsKey('clear_power_grid'), isFalse);
      });

      testWidgets('any grid over a stored grid sends clear_power_grid', (
        tester,
      ) async {
        final http = _http(
          'draft',
          gridId: 'g2',
          grids: [_grid('g1', 230), _grid('g2', 400)],
        );
        await _pump(tester, http, const QuotationScreen(id: 'q1'));
        await tester.tap(find.byKey(const ValueKey('grid-NL-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Any grid in this country').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save draft'));
        await tester.pumpAndSettle();
        final put = http.bodies['PUT /api/v1/quotations/q1'] as Map;
        expect(put['clear_power_grid'], true);
        expect(put.containsKey('power_grid_id'), isFalse);
      });

      testWidgets('the stored grid is sent again when left alone', (
        tester,
      ) async {
        final http = _http(
          'draft',
          gridId: 'g2',
          grids: [_grid('g1', 230), _grid('g2', 400)],
        );
        await _pump(tester, http, const QuotationScreen(id: 'q1'));
        await tester.tap(find.text('Save draft'));
        await tester.pumpAndSettle();
        final put = http.bodies['PUT /api/v1/quotations/q1'] as Map;
        expect(put['power_grid_id'], 'g2');
        expect(put.containsKey('clear_power_grid'), isFalse);
      });

      testWidgets('is cleared when the country changes', (tester) async {
        final http = _http(
          'draft',
          grids: [_grid('g1', 230), _grid('g2', 400)],
        );
        await _pump(tester, http, const QuotationScreen(id: 'q1'));
        await tester.tap(find.byKey(const ValueKey('grid-NL-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('230 V 1ph 50 Hz').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('deliveryCountry')),
          'FR',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(
          (http.bodies['POST /api/v1/pricing/preview'] as Map).containsKey(
            'power_grid_id',
          ),
          isFalse,
        );
      });

      testWidgets('is hidden for a stock purpose', (tester) async {
        await _pump(
          tester,
          _http(
            'draft',
            purpose: 'stock',
            grids: [_grid('g1', 230), _grid('g2', 400)],
          ),
          const QuotationScreen(id: 'q1'),
        );
        expect(find.text('Power grid'), findsNothing);
      });
    });
  });
}
