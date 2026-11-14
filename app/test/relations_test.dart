import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/products/power_grids_dialog.dart';
import 'package:tradocraft_app/features/products/related_tab.dart';
import 'package:tradocraft_app/features/products/relations_dialog.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';
import 'power_tab_test.dart' show grid, productJson;

Map<String, Object?> rule(
  String id, {
  String kind = 'incompatible',
  String? aProduct = 'PUMP-1',
  String? aFamily,
  String? bProduct,
  String? bFamily = 'HOSE',
  bool bidirectional = true,
  int strength = 50,
  String note = '',
  bool active = true,
}) => {
  'id': id,
  'kind': kind,
  'active': active,
  'bidirectional': bidirectional,
  'strength': strength,
  'note': note,
  if (aProduct != null) ...{'a_product_id': 'p1', 'a_product_code': aProduct},
  if (aFamily != null) ...{'a_family_id': 'f1', 'a_family_code': aFamily},
  if (bProduct != null) ...{'b_product_id': 'p2', 'b_product_code': bProduct},
  if (bFamily != null) ...{'b_family_id': 'f2', 'b_family_code': bFamily},
};

Map<String, Object?> suggestion(
  String id, {
  String reason = 'rule',
  int? strength = 80,
  double? confidence,
}) => {
  'product_id': id,
  'product_code': 'CTRL-$id',
  'product_name': 'Controller $id',
  'reason': reason,
  'because_of_code': 'PUMP-1',
  'note': '',
  'strength': ?strength,
  'confidence': ?confidence,
};

final families = [
  {
    'id': 'f1',
    'code': 'PUMP',
    'name': 'Pumps',
    'active': true,
    'product_count': 3,
  },
  {
    'id': 'f2',
    'code': 'HOSE',
    'name': 'Hoses',
    'active': true,
    'product_count': 2,
  },
];

FakeHttp http({
  List<String> perms = const ['products.read', 'products.write'],
  List<Object?> rules = const [],
  List<Object?> suggestions = const [],
  Object? Function(Object?)? create,
  List<Object?> grids = const [],
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/products/p1/related': (_) => {
    'rules': rules,
    'suggestions': suggestions,
  },
  'GET /api/v1/product-relations': (_) => rules,
  'POST /api/v1/product-relations': create ?? (b) => rule('new'),
  'PUT /api/v1/product-relations/r1': (b) => rule('r1'),
  'GET /api/v1/product-families': (_) => families,
  'GET /api/v1/products': (_) => {
    'items': [
      {...productJson(), 'id': 'p2', 'code': 'HOSE-9', 'name': 'Hose 9'},
    ],
    'total': 1,
  },
  'GET /api/v1/power-grids': (_) => grids,
  'POST /api/v1/power-grids': (b) => grid('new'),
  'PUT /api/v1/power-grids/g1': (b) => grid('g1'),
});

Future<void> pump(WidgetTester tester, FakeHttp h, Widget home) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(h))],
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

Future<void> openDialog(WidgetTester tester, FakeHttp h, Widget dialog) async {
  await pump(
    tester,
    h,
    Builder(
      builder: (context) => TextButton(
        onPressed: () =>
            showDialog<void>(context: context, builder: (_) => dialog),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> chooseOption(
  WidgetTester tester,
  Key dropdown,
  String text,
) async {
  await tester.tap(find.byKey(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Product product() => Product.fromJson(productJson());

void main() {
  group('related tab', () {
    testWidgets('shows rules grouped by kind and suggestions', (tester) async {
      await pump(
        tester,
        http(
          rules: [
            rule('r1'),
            rule(
              'r2',
              kind: 'suggested',
              aProduct: null,
              aFamily: 'PUMP',
              bProduct: 'CTRL-1',
              bFamily: null,
              strength: 70,
              note: 'Needs a controller',
            ),
          ],
          suggestions: [
            suggestion('1'),
            suggestion(
              '2',
              reason: 'often_bought_together',
              strength: null,
              confidence: 0.45,
            ),
          ],
        ),
        RelatedTab(product: product()),
      );
      expect(find.text('Incompatible'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      expect(find.text('PUMP-1 ↔ Family HOSE'), findsOneWidget);
      expect(find.text('Family PUMP ↔ CTRL-1'), findsOneWidget);
      expect(find.textContaining('Needs a controller'), findsOneWidget);
      expect(find.text('CTRL-1 · Controller 1'), findsOneWidget);
      expect(find.text('Rule'), findsOneWidget);
      expect(find.text('Often bought together'), findsOneWidget);
      expect(find.text('Strength 80'), findsOneWidget);
      expect(find.text('Confidence 45 %'), findsOneWidget);
    });

    testWidgets('read-only users cannot add rules', (tester) async {
      await pump(
        tester,
        http(perms: ['products.read']),
        RelatedTab(product: product()),
      );
      expect(find.text('No rules apply to this product.'), findsOneWidget);
      expect(find.text('No suggestions yet.'), findsOneWidget);
      expect(find.text('Add rule'), findsNothing);
    });

    testWidgets('adding a rule opens the editor prefilled with this product', (
      tester,
    ) async {
      final h = http();
      await pump(tester, h, RelatedTab(product: product()));
      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('a-product')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'PUMP-1',
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('b-type')),
          matching: find.text('Family'),
        ),
      );
      await tester.pumpAndSettle();
      await chooseOption(tester, const ValueKey('b-family'), 'HOSE · Hoses');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/product-relations'] as Map;
      expect(body['a_product_id'], 'p1');
      expect(body['b_family_id'], 'f2');
      expect(body['kind'], 'suggested');
      expect(body['strength'], 50);
    });
  });

  group('relations dialog', () {
    testWidgets('lists rules and filters by kind', (tester) async {
      final h = http(rules: [rule('r1', note: 'Wrong thread')]);
      await openDialog(tester, h, const RelationsDialog());
      expect(find.text('PUMP-1 ↔ Family HOSE'), findsOneWidget);
      expect(find.textContaining('Wrong thread'), findsOneWidget);
      await chooseOption(
        tester,
        const ValueKey('relation-filter'),
        'Suggested',
      );
      expect(h.queries.last['kind'], 'suggested');
    });

    testWidgets('creates a product-versus-family rule', (tester) async {
      final h = http();
      await openDialog(tester, h, const RelationsDialog());
      await tester.tap(find.text('New relation'));
      await tester.pumpAndSettle();
      await chooseOption(
        tester,
        const ValueKey('relation-kind'),
        'Incompatible',
      );
      // Strength is only for suggested rules.
      expect(find.byKey(const ValueKey('relation-strength')), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('a-product')),
          matching: find.byType(TextField),
        ),
        'hose',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('HOSE-9 · Hose 9').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('b-type')),
          matching: find.text('Family'),
        ),
      );
      await tester.pumpAndSettle();
      await chooseOption(tester, const ValueKey('b-family'), 'PUMP · Pumps');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/product-relations'] as Map;
      expect(body['kind'], 'incompatible');
      expect(body['a_product_id'], 'p2');
      expect(body['b_family_id'], 'f1');
      expect(body.containsKey('a_family_id'), isFalse);
      expect(body.containsKey('b_product_id'), isFalse);
      expect(body.containsKey('strength'), isFalse);
      expect(body['bidirectional'], true);
    });

    testWidgets(
      'creates a family-versus-product suggested rule with strength',
      (tester) async {
        final h = http();
        await openDialog(tester, h, const RelationsDialog());
        await tester.tap(find.text('New relation'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('a-type')),
            matching: find.text('Family'),
          ),
        );
        await tester.pumpAndSettle();
        await chooseOption(tester, const ValueKey('a-family'), 'HOSE · Hoses');
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('b-product')),
            matching: find.byType(TextField),
          ),
          'hose',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('HOSE-9 · Hose 9').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('relation-strength')),
          '90',
        );
        await tester.tap(find.byKey(const ValueKey('relation-bidirectional')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        final body = h.bodies['POST /api/v1/product-relations'] as Map;
        expect(body['kind'], 'suggested');
        expect(body['a_family_id'], 'f2');
        expect(body['b_product_id'], 'p2');
        expect(body['strength'], 90);
        expect(body['bidirectional'], false);
      },
    );

    testWidgets('both sides are required and strength is checked', (
      tester,
    ) async {
      final h = http();
      await openDialog(tester, h, const RelationsDialog());
      await tester.tap(find.text('New relation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a product or a family on both sides.'),
        findsOneWidget,
      );
      expect(h.requests, isNot(contains('POST /api/v1/product-relations')));
    });

    testWidgets('a duplicate (409) is shown in the editor', (tester) async {
      final h = http(
        create: (_) => const FakeStatus(409, {
          'error': 'conflict',
          'message': 'This relation already exists',
        }),
      );
      await openDialog(tester, h, const RelationsDialog());
      await tester.tap(find.text('New relation'));
      await tester.pumpAndSettle();
      for (final side in ['a', 'b']) {
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey('$side-type')),
            matching: find.text('Family'),
          ),
        );
        await tester.pumpAndSettle();
        await chooseOption(tester, ValueKey('$side-family'), 'PUMP · Pumps');
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('This relation already exists'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('editing a rule puts to its id', (tester) async {
      final h = http(rules: [rule('r1')]);
      await openDialog(tester, h, const RelationsDialog());
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['PUT /api/v1/product-relations/r1'] as Map;
      expect(body['a_product_id'], 'p1');
      expect(body['b_family_id'], 'f2');
    });
  });

  group('power grids dialog', () {
    testWidgets('lists grids and filters by country', (tester) async {
      final h = http(grids: [grid('g1'), grid('g2', voltage: 400, phases: 3)]);
      await openDialog(tester, h, const PowerGridsDialog());
      expect(find.text('NL · 230 V 1ph 50 Hz'), findsOneWidget);
      expect(find.text('NL · 400 V 3ph 50 Hz'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('grid-filter')), 'be');
      await tester.pumpAndSettle();
      expect(h.queries.last['country'], 'BE');
    });

    testWidgets('creates a grid with an uppercased country', (tester) async {
      final h = http();
      await openDialog(tester, h, const PowerGridsDialog());
      await tester.tap(find.text('New power grid'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('grid-country')), 'jp');
      await tester.enterText(find.byKey(const ValueKey('grid-voltage')), '100');
      await chooseOption(tester, const ValueKey('grid-frequency'), '60');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/power-grids'] as Map;
      expect(body['country_code'], 'JP');
      expect(body['voltage_v'], 100);
      expect(body['phases'], 1);
      expect(body['frequency_hz'], 60);
      expect(body['active'], true);
    });

    testWidgets('an incomplete grid is refused and an edit puts to its id', (
      tester,
    ) async {
      final h = http(grids: [grid('g1')]);
      await openDialog(tester, h, const PowerGridsDialog());
      await tester.tap(find.text('New power grid'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('two-letter country code'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await chooseOption(tester, const ValueKey('grid-phases'), '3');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['PUT /api/v1/power-grids/g1'] as Map;
      expect(body['phases'], 3);
      expect(body['country_code'], 'NL');
    });
  });
}
