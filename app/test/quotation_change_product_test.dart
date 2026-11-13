import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

/// id -> [code, pricing_type]
const _products = {
  'p1': ['BASE', 'list'],
  'p2': ['UNIT-2', 'list'],
  'p3': ['FRAME', 'list'],
  'p4': ['COAT', 'list'],
  'p5': ['PCT', 'list'],
  'pA': ['NEW-A', 'list'],
  'pB': ['NEW-B', 'list'],
  'pC': ['NEW-C', 'list'],
  'pN': ['NET-1', 'net'],
  'pI': ['IND-1', 'indicative'],
};

/// Default production remark per product id (none unless a test sets one).
final _defaults = <String, String>{};

Map<String, Object?> _product(String id) => {
  'default_production_remark': ?_defaults[id],
  'id': id,
  'code': _products[id]![0],
  'name': 'Name of ${_products[id]![0]}',
  'description': '',
  'unit': 'pcs',
  'product_type': 'manufactured',
  'tracking': 'none',
  'pricing_type': _products[id]![1],
  'vat_rate': '21',
  'active': true,
};

Map<String, Object?> _option(String id, {bool required = false}) => {
  'option_product_id': id,
  'option_code': _products[id]![0],
  'option_name': 'Name of ${_products[id]![0]}',
  'default_quantity': '1',
  'required': required,
  'sort_order': 0,
  'active': true,
  'option_active': true,
};

Map<String, Object?> _line(
  int position,
  String id, {
  String qty = '1',
  String discount = '0',
  int? parent,
  String? percent,
  Map<String, Object?> extra = const {},
}) => {
  'position': position,
  'product_id': id,
  'product_code': _products[id]![0],
  'description': 'Name of ${_products[id]![0]}',
  'unit': 'pcs',
  'quantity': qty,
  'list_unit_price': '100.0000',
  'line_discount_percent': discount,
  'pricing_type': _products[id]![1],
  'rebate_percent': '0',
  'rebate_source': 'general',
  'price_confirmed': true,
  'net_unit_price': '100.0000',
  'line_total': '100.00',
  'vat_rate': '21',
  'parent_position': ?parent,
  'percent_of_parent': ?percent,
  if (percent != null) 'percent_base': 'parent_list_unit_price',
  ...extra,
};

/// BASE (3 pcs, 10 % discount, remarks, section) with sub-lines UNIT-2 (+ COAT below it), FRAME and
/// a percentage line.
List<Object?> _lines() => [
  _line(
    1,
    'p1',
    qty: '3',
    discount: '10',
    extra: {
      'production_remark': 'Weld first',
      'customer_remark': 'On a pallet',
      'section': 'Hall 1',
      'comment': 'segment 2',
    },
  ),
  _line(2, 'p2', qty: '2', parent: 1),
  _line(3, 'p4', parent: 2),
  _line(4, 'p3', parent: 1),
  _line(5, 'p5', parent: 1, percent: '20'),
];

Map<String, Object?> _quotation(String status, List<Object?> lines) => {
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
  'suggestions': <Object?>[],
  'vat_groups': [
    {'vat_rate': '21', 'base': '100.00', 'vat': '21.00'},
  ],
};

/// The option catalogues of the products. `null` makes the request fail.
Map<String, List<Object?>>? _catalogues() => {
  'p1': [_option('p2'), _option('p3')],
  'pA': [_option('p2'), _option('p4', required: true)],
  'pB': [_option('p3')],
  'pC': [],
  'pN': [],
  'pI': [],
};

FakeHttp _http({
  String status = 'draft',
  List<Object?>? lines,
  Map<String, List<Object?>>? catalogues,
  bool failCatalogues = false,
}) {
  final cats = catalogues ?? _catalogues()!;
  final stored = lines ?? _lines();
  late final FakeHttp http;
  http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(['quotations.read', 'quotations.write']),
    'GET /api/v1/quotations/q1': (_) => _quotation(status, stored),
    'PUT /api/v1/quotations/q1': (_) => _quotation(status, stored),
    'POST /api/v1/quotations/q1/send': (_) => _quotation('sent', stored),
    'GET /api/v1/customers/c2': (_) => {...customerJson()},
    'GET /api/v1/power-grids': (_) => <Object?>[],
    'GET /api/v1/products': (_) => {
      // Only the products matching the typed text, so that the wanted one is on screen.
      'items': [
        for (final id in ['pA', 'pB', 'pC', 'pN', 'pI'])
          if (_products[id]![0] == http.queries.last['q']) _product(id),
      ],
      'total': 1,
    },
    for (final id in _products.keys) ...{
      'GET /api/v1/products/$id': (_) => _product(id),
      'GET /api/v1/products/$id/options': (_) => failCatalogues
          ? const FakeStatus(500, {'error': 'internal', 'message': 'boom'})
          : cats[id] ?? <Object?>[],
    },
    // Echoes the lines it was asked to price.
    'POST /api/v1/pricing/preview': (body) {
      final sent = ((body as Map)['lines'] as List).cast<Map>();
      final unconfirmed = sent
          .where(
            (l) =>
                _products[l['product_id']]![1] == 'indicative' &&
                l['unit_price'] == null &&
                l['percent_of_parent'] == null,
          )
          .length;
      return {
        'price_zone_code': 'Z2',
        'customer_discount_percent': '0',
        'quote_date': '2026-11-05',
        'price_date': '2026-11-05',
        'unconfirmed_lines': unconfirmed,
        'warnings': <Object?>[],
        'suggestions': <Object?>[],
        'lines': [
          for (final (i, l) in sent.indexed)
            _line(i + 1, l['product_id'] as String),
        ],
        'vat_groups': [
          {'vat_rate': '21', 'base': '100.00', 'vat': '21.00'},
        ],
        'subtotal': '100.00',
        'vat_total': '21.00',
        'total': '121.00',
      };
    },
  });
  return http;
}

Future<void> _pump(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1600, 1600);
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
        home: const Scaffold(body: QuotationScreen(id: 'q1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the picker of the first line and chooses [code].
Future<void> _change(WidgetTester tester, String code) async {
  await tester.tap(find.byTooltip('Change product'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('change-product-dialog')),
      matching: find.byType(TextField),
    ),
    code,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('$code · Name of $code'));
  await tester.pumpAndSettle();
}

List<Map> _preview(FakeHttp http) =>
    ((http.bodies['POST /api/v1/pricing/preview'] as Map)['lines'] as List)
        .cast<Map>();

int _previews(FakeHttp http) =>
    http.requests.where((r) => r == 'POST /api/v1/pricing/preview').length;

Future<void> _save(WidgetTester tester, FakeHttp http) async {
  await tester.tap(find.text('Save draft'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('changing the product keeps quantity, discount and remarks', (
    tester,
  ) async {
    final http = _http();
    await _pump(tester, http);
    // The stored description is what the quotation shows (and re-sends) today.
    expect(_preview(http)[0]['description'], 'Name of BASE');
    final before = _previews(http);

    await _change(tester, 'NEW-B');

    expect(_previews(http), greaterThan(before), reason: 'repriced');
    final first = _preview(http)[0];
    expect(first['product_id'], 'pB');
    expect(first['quantity'], '3');
    expect(first['line_discount_percent'], '10');
    expect(first['production_remark'], 'Weld first');
    expect(first['customer_remark'], 'On a pallet');
    expect(first['section'], 'Hall 1');
    expect(first['comment'], 'segment 2');
    expect(first['description'], isNull, reason: 'the server names the line');
    // Sub-lines keep their quantities and structure.
    expect(_preview(http).map((l) => l['product_id']), [
      'pB',
      'p2',
      'p4',
      'p3',
      'p5',
    ]);
    expect(_preview(http)[1]['quantity'], '2');
    expect(_preview(http)[2]['parent_position'], 2);
    expect(_preview(http)[4]['percent_of_parent'], '20');
    expect(find.text('Name of NEW-B'), findsOneWidget);
    expect(find.text('Name of BASE'), findsNothing);
  });

  testWidgets('the saved payload has the new product and no stale name', (
    tester,
  ) async {
    final http = _http();
    await _pump(tester, http);
    await _change(tester, 'NEW-B');
    await _save(tester, http);
    final saved =
        ((http.bodies['PUT /api/v1/quotations/q1'] as Map)['lines'] as List)
            .cast<Map>();
    expect(saved[0]['product_id'], 'pB');
    expect(saved[0]['description'], isNull);
    expect(saved[0]['quantity'], '3');
    expect(saved[0]['customer_remark'], 'On a pallet');
    // The other lines keep theirs.
    expect(saved[1]['description'], 'Name of UNIT-2');
  });

  testWidgets('a net priced product clears the discount and says so', (
    tester,
  ) async {
    final http = _http();
    await _pump(tester, http);
    await _change(tester, 'NET-1');
    expect(_preview(http)[0]['line_discount_percent'], '0');
    expect(
      find.text('NET-1 has a net price: the line discount was cleared.'),
      findsOneWidget,
    );
  });

  testWidgets('an indicative product needs its price confirmed', (
    tester,
  ) async {
    final http = _http();
    await _pump(tester, http);
    await _change(tester, 'IND-1');
    expect(_preview(http)[0]['unit_price'], isNull);
    expect(
      find.text(
        'IND-1 has an indicative price: confirm the price before sending.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('indicative price(s) to confirm'),
      findsOneWidget,
    );
  });

  testWidgets('options the new product does not offer are marked and counted', (
    tester,
  ) async {
    final http = _http();
    await _pump(tester, http);
    // BASE offers UNIT-2 and FRAME: nothing marked yet (the COAT below UNIT-2 is judged by UNIT-2,
    // which has no catalogue; the percentage line is never judged).
    expect(find.byKey(const ValueKey('not-offered')), findsNothing);

    await _change(tester, 'NEW-B');
    // NEW-B offers FRAME only: UNIT-2 is marked, FRAME and the percentage line are not.
    expect(find.byKey(const ValueKey('not-offered')), findsOneWidget);
    expect(find.text('Not offered with NEW-B'), findsOneWidget);
    expect(
      find.text('1 option(s) do not apply to NEW-B: remove them.'),
      findsOneWidget,
    );
    // Nothing was removed automatically.
    expect(_preview(http), hasLength(5));
  });

  testWidgets('Remove takes out the marked line and its sub-lines only', (
    tester,
  ) async {
    final http = _http();
    await _pump(tester, http);
    await _change(tester, 'NEW-B');
    await tester.tap(find.byKey(const ValueKey('remove-marked-p2')));
    await tester.pumpAndSettle();
    expect(_preview(http).map((l) => l['product_id']), ['pB', 'p3', 'p5']);
    expect(find.byKey(const ValueKey('not-offered')), findsNothing);
    expect(find.textContaining('do not apply'), findsNothing);
  });

  testWidgets('a main product without options marks nothing', (tester) async {
    final http = _http();
    await _pump(tester, http);
    await _change(tester, 'NEW-C');
    expect(find.byKey(const ValueKey('not-offered')), findsNothing);
    expect(find.textContaining('do not apply'), findsNothing);
    expect(_preview(http), hasLength(5));
  });

  testWidgets('a failing catalogue request marks nothing and blocks nothing', (
    tester,
  ) async {
    final http = _http(failCatalogues: true);
    await _pump(tester, http);
    await _change(tester, 'NEW-B');
    expect(find.byKey(const ValueKey('not-offered')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await _save(tester, http);
    final saved =
        ((http.bodies['PUT /api/v1/quotations/q1'] as Map)['lines'] as List);
    expect(saved.first['product_id'], 'pB');
  });

  testWidgets('the required options of the new product are offered', (
    tester,
  ) async {
    final http = _http();
    await _pump(tester, http);
    await _change(tester, 'NEW-A');
    // UNIT-2 is already on the line, so only COAT is offered, ticked and fixed.
    expect(find.byKey(const ValueKey('options-chooser')), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-option-p2')), findsNothing);
    final coat = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('choose-option-p4')),
    );
    expect(coat.value, true);
    expect(coat.onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('options-add')));
    await tester.pumpAndSettle();
    final lines = _preview(http);
    expect(lines.where((l) => l['product_id'] == 'p4'), hasLength(2));
    expect(lines.first['product_id'], 'pA');
  });

  testWidgets('cancelling the offered options keeps the swap', (tester) async {
    final http = _http();
    await _pump(tester, http);
    await _change(tester, 'NEW-A');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_preview(http).first['product_id'], 'pA');
    expect(_preview(http), hasLength(5));
  });

  testWidgets('the action is on main lines of a draft only', (tester) async {
    final http = _http();
    await _pump(tester, http);
    expect(find.byTooltip('Change product'), findsOneWidget);
    expect(find.byTooltip('Remove line'), findsNWidgets(5));
  });

  testWidgets('a sent quotation cannot change its product', (tester) async {
    final http = _http(status: 'sent');
    await _pump(tester, http);
    expect(find.byTooltip('Change product'), findsNothing);
  });

  testWidgets('a reloaded quotation shows the marks', (tester) async {
    final http = _http(
      catalogues: {
        'p1': [_option('p3')],
      },
    );
    await _pump(tester, http);
    expect(find.text('Not offered with BASE'), findsOneWidget);
    // No swap happened: no banner, only the mark on the line.
    expect(find.textContaining('do not apply'), findsNothing);
  });

  testWidgets('sending with marked options is not blocked, only noted', (
    tester,
  ) async {
    final http = _http(
      catalogues: {
        'p1': [_option('p3')],
      },
    );
    await _pump(tester, http);
    await tester.tap(find.text('Mark as sent'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/quotations/q1/send'));
    expect(
      find.text(
        'Sent with 1 option(s) that do not apply to their main product.',
      ),
      findsOneWidget,
    );
  });

  group('production remark on a swap', () {
    setUp(() {
      _defaults
        ..['p1'] = 'Weld first'
        ..['pB'] = 'Paint after';
    });
    tearDown(_defaults.clear);

    testWidgets('the unedited default of the old product is cleared', (
      tester,
    ) async {
      // The line carries 'Weld first', which is exactly BASE's default.
      final http = _http();
      await _pump(tester, http);
      await _change(tester, 'NEW-B');
      // Empty, so the server applies NEW-B's default; the old text is never sent.
      expect(_preview(http)[0]['production_remark'], '');
      await _save(tester, http);
      final saved =
          ((http.bodies['PUT /api/v1/quotations/q1'] as Map)['lines'] as List);
      expect(saved.first['production_remark'], '');
    });

    testWidgets('an edited remark is kept', (tester) async {
      final lines = _lines();
      (lines.first as Map)['production_remark'] = 'Weld twice';
      final http = _http(lines: lines);
      await _pump(tester, http);
      await _change(tester, 'NEW-B');
      expect(_preview(http)[0]['production_remark'], 'Weld twice');
    });

    testWidgets('an empty remark stays empty', (tester) async {
      final lines = _lines();
      (lines.first as Map)['production_remark'] = '';
      final http = _http(lines: lines);
      await _pump(tester, http);
      await _change(tester, 'NEW-B');
      expect(_preview(http)[0]['production_remark'], '');
    });
  });
}
