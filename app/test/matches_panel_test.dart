import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/opportunities/baseline_section.dart';
import 'package:tradocraft_app/features/opportunities/matches_panel.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _reason(String check, String status, String message) => {
  'check': check,
  'status': status,
  'message': message,
};

Map<String, Object?> _match(
  String id,
  String name,
  String status, [
  List<Map<String, Object?>> reasons = const [],
]) => {
  'id': id,
  'code': 'C-$id',
  'name': name,
  'status': status,
  'reasons': reasons,
};

const _fail =
    'clock_dial: dial_diameter_mm 2000 is outside dial_size_mm 600..1250';
const _ok =
    'clock_dial: dial_diameter_mm 2000 is within dial_size_mm 1500..2500';

// Deliberately not in display order.
Map<String, Object?> _page({List<Object?>? items, int total = 3}) => {
  'items':
      items ??
      [
        _match('p3', 'Small unit', 'unsuitable', [
          _reason('rule:Dial size fits product', 'fail', _fail),
        ]),
        _match('p2', 'Plain unit', 'unknown', [
          _reason(
            'rule:Dial size fits product',
            'unknown',
            'clock_dial: the product has no dial_size_mm, the fit of dial_diameter_mm 2000 is unknown',
          ),
        ]),
        _match('p1', 'Big unit', 'suitable', [
          _reason('rule:Dial size fits product', 'ok', _ok),
        ]),
      ],
  'total': total,
  'counts': {'suitable': 1, 'unknown': 1, 'unsuitable': 1},
};

Map<String, Object?> _item(String id, String type) => {
  'id': id,
  'parent_id': null,
  'type_code': type,
  'name': null,
  'quantity': 1,
  'values': <String, Object?>{},
  'sort_order': 0,
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
  'children': <Object?>[],
};

FakeHttp _http({
  List<String> perms = const [
    'opportunities.read',
    'opportunities.write',
    'products.read',
  ],
  Map<String, Object?> Function()? page,
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/opportunities/o1/product-matches': (_) => (page ?? _page)(),
  'GET /api/v1/opportunities/o1/baseline': (_) => [_item('d1', 'clock_dial')],
  'GET /api/v1/baseline-item-types': (_) => [
    {
      'id': 't',
      'code': 'clock_dial',
      'name': 'Clock dial',
      'allowed_parent_codes': <String>[],
      'allow_top_level': true,
      'sort_order': 0,
      'active': true,
    },
  ],
  'GET /api/v1/attribute-definitions': (_) => <Object?>[],
});

Future<void> _pump(WidgetTester tester, FakeHttp h, Widget child) async {
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
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(meProvider);
              return SingleChildScrollView(child: child);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'lists every product, suitable first, then unknown, then not suitable',
    (tester) async {
      final h = _http();
      await _pump(tester, h, const MatchesPanel(opportunityId: 'o1'));
      expect(find.text('Product matches'), findsOneWidget);
      final y = [
        for (final id in ['p1', 'p2', 'p3'])
          tester.getTopLeft(find.byKey(ValueKey('match-$id'))).dy,
      ];
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: '$y');
      final i = h.requests.indexOf(
        'GET /api/v1/opportunities/o1/product-matches',
      );
      expect(h.queries[i]['limit'], 500);
      expect(h.queries[i].containsKey('item_id'), isFalse);
    },
  );

  testWidgets(
    'greys out products that do not fit and shows the reason beneath',
    (tester) async {
      await _pump(tester, _http(), const MatchesPanel(opportunityId: 'o1'));
      // Suitable: full strength, reasons not spelled out.
      expect(find.byKey(const ValueKey('match-grey-p1')), findsNothing);
      expect(find.text(_ok), findsNothing);
      // Not suitable and unknown: dimmed, with the failing / unknown reason.
      for (final id in ['p2', 'p3']) {
        final o = tester.widget<Opacity>(
          find.byKey(ValueKey('match-grey-$id')),
        );
        expect(o.opacity, lessThan(1), reason: id);
      }
      expect(find.text(_fail), findsOneWidget);
      expect(
        find.textContaining('the product has no dial_size_mm'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('match-p3')),
          matching: find.text(_fail),
        ),
        findsOneWidget,
      );
      expect(find.text('Not suitable'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('Suitable'), findsOneWidget);
    },
  );

  testWidgets('shows a hint when there are no products', (tester) async {
    await _pump(
      tester,
      _http(page: () => _page(items: const [])),
      const MatchesPanel(opportunityId: 'o1'),
    );
    expect(find.text('No products to show.'), findsOneWidget);
  });

  testWidgets('is hidden without products.read', (tester) async {
    final h = _http(perms: const ['opportunities.read']);
    await _pump(tester, h, const MatchesPanel(opportunityId: 'o1'));
    expect(find.text('Product matches'), findsNothing);
    expect(
      h.requests,
      isNot(contains('GET /api/v1/opportunities/o1/product-matches')),
    );
  });

  testWidgets('"Suggest products" on a baseline item asks for that item only', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h, const BaselineSection(opportunityId: 'o1'));
    await tester.tap(find.byKey(const ValueKey('baseline-suggest-d1')));
    await tester.pumpAndSettle();
    expect(find.text('Products for Clock dial'), findsOneWidget);
    final i = h.requests.indexOf(
      'GET /api/v1/opportunities/o1/product-matches',
    );
    expect(i, isNonNegative);
    expect(h.queries[i]['item_id'], 'd1');
    expect(find.byKey(const ValueKey('match-p1')), findsOneWidget);
    expect(find.text(_fail), findsOneWidget);
  });

  testWidgets('no suggest action without products.read', (tester) async {
    await _pump(
      tester,
      _http(perms: const ['opportunities.read']),
      const BaselineSection(opportunityId: 'o1'),
    );
    expect(find.byKey(const ValueKey('baseline-suggest-d1')), findsNothing);
  });

  testWidgets('setting an attribute in place refreshes the matches', (
    tester,
  ) async {
    final h = FakeHttp({
      ..._http().routes,
      'GET /api/v1/opportunities/o1/baseline': (_) => [
        {..._item('d1', 'clock_dial'), 'name': 'Dial'},
      ],
      'GET /api/v1/attribute-definitions': (_) => [
        {
          'id': 'x',
          'key': 'lit',
          'label': 'Lit',
          'kind': 'boolean',
          'unit': null,
          'options': <Object?>[],
          'scope': 'clock_dial',
          'sort_order': 0,
          'active': true,
        },
      ],
      'PUT /api/v1/opportunities/o1/baseline/items/d1': (_) =>
          _item('d1', 'clock_dial'),
    });
    await _pump(
      tester,
      h,
      const Column(
        children: [
          BaselineSection(opportunityId: 'o1'),
          MatchesPanel(opportunityId: 'o1'),
        ],
      ),
    );
    int loads() => h.requests
        .where((r) => r == 'GET /api/v1/opportunities/o1/product-matches')
        .length;
    final before = loads();
    await tester.tap(find.byKey(const ValueKey('baseline-chip-d1-lit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bl-attr-lit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('baseline-quick-save')));
    await tester.pumpAndSettle();
    expect(loads(), before + 1);
  });

  testWidgets('says how many of the products are shown when the list is cut', (
    tester,
  ) async {
    await _pump(
      tester,
      _http(page: () => _page(total: 700)),
      const MatchesPanel(opportunityId: 'o1'),
    );
    expect(find.text('Showing 3 of 700 products'), findsOneWidget);
  });

  testWidgets('shows no count when every product is listed', (tester) async {
    await _pump(tester, _http(), const MatchesPanel(opportunityId: 'o1'));
    expect(find.textContaining('Showing'), findsNothing);
  });

  testWidgets('the suggestion dialog says it too', (tester) async {
    await _pump(
      tester,
      _http(page: () => _page(total: 700)),
      const BaselineSection(opportunityId: 'o1'),
    );
    await tester.tap(find.byKey(const ValueKey('baseline-suggest-d1')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 3 of 700 products'), findsOneWidget);
  });
}
