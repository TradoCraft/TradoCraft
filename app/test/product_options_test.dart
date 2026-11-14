import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/products/options_tab.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _product(String id, String code, String name) => {
  'id': id,
  'code': code,
  'name': name,
  'description': '',
  'unit': 'pcs',
  'product_type': 'manufactured',
  'tracking': 'none',
  'pricing_type': 'list',
  'vat_rate': '21',
  'active': true,
};

Map<String, Object?> _option(
  String id,
  String code, {
  String qty = '1',
  bool required = false,
  bool active = true,
}) => {
  'option_product_id': id,
  'option_code': code,
  'option_name': 'Name of $code',
  'default_quantity': qty,
  'required': required,
  'sort_order': 0,
  'active': active,
  'option_active': true,
};

Map<String, Object?> _line(
  int position,
  String id,
  String code, {
  int? parent,
}) => {
  'position': position,
  'product_id': id,
  'product_code': code,
  'description': 'Name of $code',
  'unit': 'pcs',
  'quantity': '1',
  'list_unit_price': '100.0000',
  'line_discount_percent': '0',
  'pricing_type': 'list',
  'rebate_percent': '0',
  'rebate_source': 'general',
  'price_confirmed': true,
  'net_unit_price': '100.0000',
  'line_total': '100.00',
  'vat_rate': '21',
  'parent_position': ?parent,
};

Map<String, Object?> _quotation(
  List<Object?> lines, {
  String status = 'draft',
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
  'customer_discount_percent': '0',
  'currency': 'EUR',
  'quote_date': '2026-11-05',
  'purpose': 'installation',
  'shipping_status': 'not_required',
  'price_date': '2026-11-05',
  'valid_until': '2026-12-05',
  'notes': '',
  'subtotal': '100.00',
  'vat_total': '21.00',
  'total': '121.00',
  'created_by': 'u',
  'created_at': '2026-11-05T10:00:00Z',
  'updated_at': '2026-11-05T10:00:00Z',
  'lines': lines,
  'warnings': <Object?>[],
  'suggestions': [
    {
      'product_id': 'p2',
      'product_code': 'UNIT-2',
      'product_name': 'Name of UNIT-2',
      'reason': 'rule',
      'because_of_code': 'BASE',
      'note': '',
      'strength': 80,
    },
  ],
  'vat_groups': [
    {'vat_rate': '21', 'base': '100.00', 'vat': '21.00'},
  ],
};

Map<String, Object?> _preview(int lines) => {
  'price_zone_code': 'Z2',
  'customer_discount_percent': '0',
  'quote_date': '2026-11-05',
  'price_date': '2026-11-05',
  'unconfirmed_lines': 0,
  'warnings': <Object?>[],
  'suggestions': [
    {
      'product_id': 'p2',
      'product_code': 'UNIT-2',
      'product_name': 'Name of UNIT-2',
      'reason': 'rule',
      'because_of_code': 'BASE',
      'note': '',
      'strength': 80,
    },
  ],
  'lines': [for (var i = 0; i < lines; i++) _line(i + 1, 'p1', 'BASE')],
  'vat_groups': [
    {'vat_rate': '21', 'base': '100.00', 'vat': '21.00'},
  ],
  'subtotal': '100.00',
  'vat_total': '21.00',
  'total': '121.00',
};

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
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _unit = Product.fromJson(_product('p2', 'UNIT-2', 'Name of UNIT-2'));

FakeHttp _optionsHttp(
  List<Object?> stored, {
  List<String> permissions = const ['products.read', 'products.write'],
}) {
  return FakeHttp({
    'GET /api/v1/me': (_) => meJson(permissions),
    'GET /api/v1/products/p2/options': (_) => stored,
    'PUT /api/v1/products/p2/options': (body) => [
      for (final o in (body as List).cast<Map>())
        _option(
          o['option_product_id'] as String,
          'SAVED-${o['option_product_id']}',
          qty: o['default_quantity'] as String,
          required: o['required'] as bool,
        ),
    ],
  });
}

void main() {
  group('options tab', () {
    testWidgets('lists the options and saves changes as a whole', (
      tester,
    ) async {
      final http = _optionsHttp([
        _option('p3', 'FRAME', qty: '2', required: true),
        _option('p4', 'COAT', active: false),
      ]);
      await _pump(tester, http, OptionsTab(product: _unit));
      expect(find.text('FRAME · Name of FRAME'), findsOneWidget);
      expect(find.text('COAT · Name of COAT'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('option-qty-p4')),
        '3,5',
      );
      await tester.tap(find.byKey(const ValueKey('option-required-p4')));
      await tester.tap(find.byKey(const ValueKey('option-remove-p3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('options-save')));
      await tester.pumpAndSettle();

      final body = http.bodies['PUT /api/v1/products/p2/options'] as List;
      expect(body, hasLength(1));
      expect(body.single['option_product_id'], 'p4');
      expect(body.single['default_quantity'], '3.5');
      expect(body.single['required'], true);
      expect(body.single['active'], false, reason: 'the stored state is kept');
      expect(find.text('Options saved.'), findsOneWidget);
    });

    testWidgets('a quantity of 0 is refused before saving', (tester) async {
      final http = _optionsHttp([_option('p4', 'COAT')]);
      await _pump(tester, http, OptionsTab(product: _unit));
      await tester.enterText(find.byKey(const ValueKey('option-qty-p4')), '0');
      await tester.tap(find.byKey(const ValueKey('options-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a quantity greater than 0 for every option.'),
        findsOneWidget,
      );
      expect(http.requests, isNot(contains('PUT /api/v1/products/p2/options')));
    });

    testWidgets('without products.write the options are read-only', (
      tester,
    ) async {
      final http = _optionsHttp(
        [_option('p4', 'COAT')],
        permissions: ['products.read'],
      );
      await _pump(tester, http, OptionsTab(product: _unit));
      expect(find.text('COAT · Name of COAT'), findsOneWidget);
      expect(find.byKey(const ValueKey('options-save')), findsNothing);
      expect(find.byKey(const ValueKey('option-remove-p4')), findsNothing);
    });

    testWidgets('a product without options says so', (tester) async {
      await _pump(tester, _optionsHttp([]), OptionsTab(product: _unit));
      expect(find.text('This product has no options.'), findsOneWidget);
    });
  });

  group('adding a product to a quotation', () {
    FakeHttp quoteHttp(List<Object?> options, {List<Object?>? stored}) {
      var previews = 0;
      return FakeHttp({
        'GET /api/v1/me': (_) =>
            meJson(['quotations.read', 'quotations.write']),
        'GET /api/v1/quotations/q1': (_) =>
            _quotation(stored ?? [_line(1, 'p1', 'BASE')]),
        'PUT /api/v1/quotations/q1': (_) =>
            _quotation([_line(1, 'p1', 'BASE')]),
        'GET /api/v1/customers/c2': (_) => {...customerJson(), 'id': 'c2'},
        'GET /api/v1/products/p1': (_) =>
            _product('p1', 'BASE', 'Name of BASE'),
        'GET /api/v1/products/p2': (_) =>
            _product('p2', 'UNIT-2', 'Name of UNIT-2'),
        'GET /api/v1/products/p3': (_) =>
            _product('p3', 'FRAME', 'Name of FRAME'),
        'GET /api/v1/products/p4': (_) =>
            _product('p4', 'COAT', 'Name of COAT'),
        'GET /api/v1/products/p2/options': (_) => options,
        'GET /api/v1/power-grids': (_) => <Object?>[],
        'POST /api/v1/pricing/preview': (_) => _preview(++previews),
      });
    }

    List<Map> previewLines(FakeHttp http) =>
        ((http.bodies['POST /api/v1/pricing/preview'] as Map)['lines'] as List)
            .cast<Map>();

    testWidgets(
      'the chooser adds required options and the ticked optional ones as child lines',
      (tester) async {
        final http = quoteHttp([
          _option('p3', 'FRAME', qty: '2', required: true),
          _option('p4', 'COAT'),
        ]);
        await _pump(tester, http, const QuotationScreen(id: 'q1'));
        await tester.tap(find.widgetWithText(OutlinedButton, 'Add'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('options-chooser')), findsOneWidget);
        // The required option is ticked and fixed; the optional one is the user's choice.
        final required = tester.widget<CheckboxListTile>(
          find.byKey(const ValueKey('choose-option-p3')),
        );
        expect(required.value, true);
        expect(required.onChanged, isNull);
        await tester.tap(find.byKey(const ValueKey('choose-option-p4')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('options-add')));
        await tester.pumpAndSettle();

        final lines = previewLines(http);
        expect(lines.map((l) => l['product_id']), ['p1', 'p2', 'p3', 'p4']);
        expect(lines[0]['parent_position'], isNull);
        expect(lines[1]['parent_position'], isNull);
        expect(lines[2]['parent_position'], 2);
        expect(lines[3]['parent_position'], 2);
        expect(lines[2]['quantity'].toString(), anyOf('2', '2.0'));
        expect(lines[3]['quantity'].toString(), anyOf('1', '1.0'));
      },
    );

    testWidgets(
      'without options in the dialog only the required ones are added',
      (tester) async {
        final http = quoteHttp([
          _option('p3', 'FRAME', required: true),
          _option('p4', 'COAT'),
        ]);
        await _pump(tester, http, const QuotationScreen(id: 'q1'));
        await tester.tap(find.widgetWithText(OutlinedButton, 'Add'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('options-skip')));
        await tester.pumpAndSettle();
        expect(previewLines(http).map((l) => l['product_id']), [
          'p1',
          'p2',
          'p3',
        ]);
      },
    );

    testWidgets('only required options are added without a dialog', (
      tester,
    ) async {
      final http = quoteHttp([_option('p3', 'FRAME', required: true)]);
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('options-chooser')), findsNothing);
      expect(previewLines(http).map((l) => l['product_id']), [
        'p1',
        'p2',
        'p3',
      ]);
    });

    testWidgets(
      'the sub-item chooser adds ticked options and several searched products below the line',
      (tester) async {
        final http = quoteHttp([]);
        http.routes['GET /api/v1/products/p1/options'] = (_) => [
          _option('p3', 'FRAME', qty: '2'),
        ];
        http.routes['GET /api/v1/products'] = (_) => {
          'items': [
            _product('p4', 'COAT', 'Name of COAT'),
            _product('p5', 'EXTRA', 'Name of EXTRA'),
          ],
          'total': 2,
        };
        http.routes['GET /api/v1/products/p5'] = (_) =>
            _product('p5', 'EXTRA', 'Name of EXTRA');
        await _pump(tester, http, const QuotationScreen(id: 'q1'));

        await tester.tap(find.byTooltip('Add sub-item').first);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sub-item-chooser')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('sub-option-p3')));
        await tester.enterText(
          find.byKey(const ValueKey('sub-item-search')),
          'co',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sub-product-p4')));
        await tester.tap(find.byKey(const ValueKey('sub-product-p5')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('sub-item-add')));
        await tester.pumpAndSettle();

        final lines = previewLines(http);
        expect(lines.map((l) => l['product_id']), ['p1', 'p3', 'p4', 'p5']);
        expect(lines.map((l) => l['parent_position']), [null, 1, 1, 1]);
        expect(lines[1]['quantity'].toString(), anyOf('2', '2.0'));
      },
    );

    testWidgets('a product without options is added as it is', (tester) async {
      final http = quoteHttp([]);
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('options-chooser')), findsNothing);
      expect(previewLines(http).map((l) => l['product_id']), ['p1', 'p2']);
    });

    testWidgets('removing a parent line removes its option lines', (
      tester,
    ) async {
      // Stored: BASE, then UNIT-2 with two option lines.
      final http = quoteHttp(
        [],
        stored: [
          _line(1, 'p1', 'BASE'),
          _line(2, 'p2', 'UNIT-2'),
          _line(3, 'p3', 'FRAME', parent: 2),
          _line(4, 'p4', 'COAT', parent: 2),
        ],
      );
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      // The structure of the stored lines survives loading: parents are sent back.
      var lines = previewLines(http);
      expect(lines.map((l) => l['parent_position']), [null, null, 2, 2]);

      // The remove buttons are in row order: BASE, UNIT-2, FRAME, COAT.
      final remove = find.byTooltip('Remove line');
      expect(remove, findsNWidgets(4));
      await tester.tap(remove.at(1));
      await tester.pumpAndSettle();
      lines = previewLines(http);
      expect(lines.map((l) => l['product_id']), ['p1']);
    });

    testWidgets('removing an option leaves its parent', (tester) async {
      final http = quoteHttp(
        [],
        stored: [_line(1, 'p2', 'UNIT-2'), _line(2, 'p3', 'FRAME', parent: 1)],
      );
      await _pump(tester, http, const QuotationScreen(id: 'q1'));
      await tester.tap(find.byTooltip('Remove line').at(1));
      await tester.pumpAndSettle();
      expect(previewLines(http).map((l) => l['product_id']), ['p2']);
    });
  });
}
