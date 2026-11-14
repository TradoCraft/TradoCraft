import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/products/suitability_tab.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> def(
  String key,
  String kind, {
  String? unit,
  List<Map<String, String>> options = const [],
}) => {
  'id': 'd-$key',
  'key': key,
  'label': 'L-$key',
  'kind': kind,
  'unit': unit,
  'options': options,
  'scope': 'product',
  'sort_order': 0,
  'active': true,
};

const _product = {
  'id': 'p1',
  'code': 'DIAL-1',
  'name': 'Dial',
  'description': '',
  'unit': 'pcs',
  'product_type': 'purchased',
  'tracking': 'none',
  'pricing_type': 'list',
  'vat_rate': '21',
  'active': true,
};

final _defs = [
  def('weight', 'number', unit: 'kg'),
  def('dial', 'range', unit: 'mm'),
  def(
    'motion',
    'select',
    options: [
      {'label': 'Flying', 'value': 'flying'},
      {'label': 'Falling', 'value': 'falling'},
    ],
  ),
  def('note', 'text'),
];

FakeHttp _http({
  List<String> perms = const ['products.read', 'products.write'],
  List<Object?>? defs,
  List<Object?> attrs = const [],
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/attribute-definitions': (_) => defs ?? _defs,
  'GET /api/v1/products/p1/attributes': (_) => attrs,
  'PUT /api/v1/products/p1/attributes': (b) => b,
});

Future<void> _pump(WidgetTester tester, FakeHttp h) async {
  tester.view.physicalSize = const Size(1400, 1800);
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
        home: Scaffold(
          body: SuitabilityTab(product: Product.fromJson(_product)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only active product-scope definitions are requested', (tester) async {
    final h = _http();
    await _pump(tester, h);
    final i = h.requests.indexOf('GET /api/v1/attribute-definitions');
    expect(h.queries[i]['scope'], 'product');
  });

  testWidgets('shows an empty state when there are no definitions', (tester) async {
    await _pump(tester, _http(defs: const []));
    expect(find.byKey(const ValueKey('suitability-empty')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
  });

  testWidgets('inactive definitions are not rendered', (tester) async {
    final inactive = def('old', 'text')..['active'] = false;
    await _pump(tester, _http(defs: [def('note', 'text'), inactive]));
    expect(find.byKey(const ValueKey('attr-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('attr-old')), findsNothing);
  });

  testWidgets('renders one input per kind with units', (tester) async {
    await _pump(tester, _http());
    expect(find.byKey(const ValueKey('attr-weight')), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('attr-dial-min')), findsOneWidget);
    expect(find.byKey(const ValueKey('attr-dial-max')), findsOneWidget);
    expect(find.byKey(const ValueKey('attr-motion')), findsOneWidget);
    expect(find.byKey(const ValueKey('attr-note')), findsOneWidget);
  });

  testWidgets('saves filled values and preserves unknown attributes', (tester) async {
    final h = _http(
      attrs: [
        {'key': 'color', 'kind': 'text', 'value': 'red'},
        {'key': 'weight', 'kind': 'number', 'value': '1', 'unit': 'kg'},
      ],
    );
    await _pump(tester, h);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('attr-weight')))
          .controller!
          .text,
      '1',
    );
    await tester.enterText(find.byKey(const ValueKey('attr-weight')), '12.5');
    await tester.enterText(find.byKey(const ValueKey('attr-dial-min')), '600');
    await tester.enterText(find.byKey(const ValueKey('attr-dial-max')), '1250');
    await tester.tap(find.byKey(const ValueKey('attr-motion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Falling').last);
    await tester.pumpAndSettle();
    await _save(tester);
    final body = h.bodies['PUT /api/v1/products/p1/attributes'] as List;
    expect(body, [
      {'key': 'color', 'kind': 'text', 'value': 'red'},
      {'key': 'weight', 'kind': 'number', 'value': '12.5', 'unit': 'kg'},
      {
        'key': 'dial',
        'kind': 'range',
        'value': '',
        'unit': 'mm',
        'value_min': '600',
        'value_max': '1250',
      },
      {'key': 'motion', 'kind': 'text', 'value': 'falling'},
    ]);
  });

  testWidgets('invalid values are refused inline and nothing is sent', (tester) async {
    final h = _http();
    await _pump(tester, h);
    await tester.enterText(find.byKey(const ValueKey('attr-weight')), 'abc');
    await tester.enterText(find.byKey(const ValueKey('attr-dial-min')), '900');
    await tester.enterText(find.byKey(const ValueKey('attr-dial-max')), '600');
    await _save(tester);
    expect(find.text('Enter a number.'), findsOneWidget);
    expect(find.text('The minimum must not exceed the maximum.'), findsOneWidget);
    expect(h.requests, isNot(contains('PUT /api/v1/products/p1/attributes')));
  });

  testWidgets('a range needs both bounds', (tester) async {
    final h = _http();
    await _pump(tester, h);
    await tester.enterText(find.byKey(const ValueKey('attr-dial-min')), '900');
    await _save(tester);
    expect(find.text('Enter both the minimum and the maximum, or neither.'), findsOneWidget);
    expect(h.requests, isNot(contains('PUT /api/v1/products/p1/attributes')));
  });

  testWidgets('without products.write the inputs are read-only', (tester) async {
    await _pump(tester, _http(perms: ['products.read']));
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('attr-note'))).enabled,
      isFalse,
    );
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
  });
}
