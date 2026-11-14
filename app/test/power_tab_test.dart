import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/products/power_tab.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> productJson() => {
  'id': 'p1',
  'code': 'PUMP-1',
  'name': 'Pump',
  'description': '',
  'unit': 'pcs',
  'product_type': 'purchased',
  'tracking': 'none',
  'pricing_type': 'list',
  'vat_rate': '21',
  'active': true,
};

Map<String, Object?> supply({
  String id = 's1',
  String current = 'ac',
  int voltage = 230,
  int? phases = 1,
  int? frequency,
  int tolerance = 10,
  int? min,
  int? max,
}) => {
  'id': id,
  'current_type': current,
  'voltage_v': voltage,
  'phases': phases,
  'frequency_hz': frequency,
  'tolerance_pct': tolerance,
  'voltage_min_v': min,
  'voltage_max_v': max,
};

Map<String, Object?> grid(
  String id, {
  String country = 'NL',
  int voltage = 230,
  int phases = 1,
  int frequency = 50,
  bool active = true,
}) => {
  'id': id,
  'country_code': country,
  'name': '$country $voltage V',
  'voltage_v': voltage,
  'phases': phases,
  'frequency_hz': frequency,
  'active': active,
};

Map<String, Object?> report(
  String status, {
  List<Object?> supported = const [],
  List<Object?> available = const [],
}) => {
  'status': status,
  'country_code': 'NL',
  'supported': supported,
  'available': available,
};

FakeHttp http({
  List<String> perms = const ['products.read', 'products.write'],
  List<Object?> supplies = const [],
  Object? Function(Object?)? compat,
  List<Object?> grids = const [],
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/products/p1/power-supplies': (_) => supplies,
  'PUT /api/v1/products/p1/power-supplies': (b) => b,
  'GET /api/v1/power-grids': (_) => grids,
  'GET /api/v1/products/p1/power-compatibility':
      compat ?? (_) => report('compatible'),
});

Future<void> pumpTab(WidgetTester tester, FakeHttp h) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(h))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PowerTab(product: Product.fromJson(productJson())),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a product without supplies is shown as not electrical', (
    tester,
  ) async {
    await pumpTab(tester, http());
    expect(find.textContaining('not an electrical product'), findsOneWidget);
  });

  testWidgets('an AC supply is saved with phases and both frequencies', (
    tester,
  ) async {
    final h = http();
    await pumpTab(tester, h);
    await tester.tap(find.text('Add supply'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('voltage-0')), '230');
    await save(tester);
    final body = h.bodies['PUT /api/v1/products/p1/power-supplies'] as List;
    expect(body, [
      {
        'current_type': 'ac',
        'voltage_v': 230,
        'phases': 1,
        'tolerance_pct': 10,
      },
    ]);
  });

  testWidgets('a DC supply has no phases or frequency', (tester) async {
    final h = http(supplies: [supply(current: 'ac', phases: 3, frequency: 50)]);
    await pumpTab(tester, h);
    expect(find.byKey(const ValueKey('phases-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('current-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DC').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('phases-0')), findsNothing);
    expect(find.byKey(const ValueKey('frequency-0')), findsNothing);
    await save(tester);
    final body = h.bodies['PUT /api/v1/products/p1/power-supplies'] as List;
    expect(body.single, {
      'current_type': 'dc',
      'voltage_v': 230,
      'tolerance_pct': 10,
    });
  });

  testWidgets('existing supplies are loaded and a 3-phase 60 Hz one is sent', (
    tester,
  ) async {
    final h = http(
      supplies: [supply(voltage: 400, phases: 3, frequency: 60, tolerance: 5)],
    );
    await pumpTab(tester, h);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('voltage-0')))
          .controller!
          .text,
      '400',
    );
    await save(tester);
    final body = h.bodies['PUT /api/v1/products/p1/power-supplies'] as List;
    expect(body.single, {
      'current_type': 'ac',
      'voltage_v': 400,
      'phases': 3,
      'frequency_hz': 60,
      'tolerance_pct': 5,
    });
  });

  testWidgets('invalid voltage, tolerance and duplicates are refused', (
    tester,
  ) async {
    final h = http(
      supplies: [
        supply(),
        supply(id: 's2'),
      ],
    );
    await pumpTab(tester, h);
    await save(tester);
    expect(find.text('The same supply is listed twice.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('tolerance-1')), '60');
    await save(tester);
    expect(find.textContaining('from 0 to 50'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('voltage-1')), '');
    await save(tester);
    expect(find.textContaining('positive whole number'), findsOneWidget);
    expect(
      h.requests,
      isNot(contains('PUT /api/v1/products/p1/power-supplies')),
    );
  });

  testWidgets('without products.write the list is read-only', (tester) async {
    await pumpTab(tester, http(perms: ['products.read'], supplies: [supply()]));
    expect(find.text('Add supply'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('voltage-0'))).enabled,
      isFalse,
    );
    // The check is still available.
    expect(find.text('Grid compatibility check'), findsOneWidget);
  });

  group('voltage range', () {
    const put = 'PUT /api/v1/products/p1/power-supplies';

    testWidgets('empty bounds are not sent and a hint explains them', (
      tester,
    ) async {
      final h = http(supplies: [supply()]);
      await pumpTab(tester, h);
      expect(find.byKey(const ValueKey('vmin-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('vmax-0')), findsOneWidget);
      expect(find.textContaining('nominal voltage'), findsWidgets);
      await save(tester);
      final body = h.bodies[put] as List;
      expect((body.single as Map).containsKey('voltage_min_v'), isFalse);
      expect((body.single as Map).containsKey('voltage_max_v'), isFalse);
    });

    testWidgets('bounds are loaded and sent for AC and DC rows', (
      tester,
    ) async {
      final h = http(
        supplies: [
          supply(min: 200, max: 250),
          supply(id: 's2', current: 'dc', voltage: 24, phases: null, min: 12, max: 30),
        ],
      );
      await pumpTab(tester, h);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vmin-1')))
            .controller!
            .text,
        '12',
      );
      await save(tester);
      final body = h.bodies[put] as List;
      expect((body[0] as Map)['voltage_min_v'], 200);
      expect((body[0] as Map)['voltage_max_v'], 250);
      expect((body[1] as Map)['voltage_min_v'], 12);
      expect((body[1] as Map)['voltage_max_v'], 30);
    });

    testWidgets('invalid combinations show an inline error and are not sent', (
      tester,
    ) async {
      final h = http(supplies: [supply()]);
      await pumpTab(tester, h);
      await tester.enterText(find.byKey(const ValueKey('vmin-0')), '200');
      await save(tester);
      expect(find.textContaining('both the minimum and the maximum'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('vmax-0')), '150');
      await save(tester);
      expect(find.textContaining('must not exceed'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('vmin-0')), '100');
      await tester.enterText(find.byKey(const ValueKey('vmax-0')), '120');
      await save(tester);
      expect(find.textContaining('nominal voltage must lie within'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('vmin-0')), '0');
      await tester.enterText(find.byKey(const ValueKey('vmax-0')), '250');
      await save(tester);
      expect(find.textContaining('from 1 to 100000'), findsOneWidget);
      expect(h.requests, isNot(contains(put)));
    });
  });

  group('compatibility check', () {
    Future<void> check(WidgetTester tester, FakeHttp h) async {
      await pumpTab(tester, h);
      await tester.enterText(find.byKey(const ValueKey('check-country')), 'nl');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Check'));
      await tester.pumpAndSettle();
    }

    testWidgets('compatible', (tester) async {
      final h = http();
      await check(tester, h);
      expect(
        find.text('Compatible with the power grid of NL.'),
        findsOneWidget,
      );
      expect(h.queries.last['country'], 'NL');
    });

    testWidgets('incompatible lists supported and available grids', (
      tester,
    ) async {
      await check(
        tester,
        http(
          compat: (_) => report(
            'incompatible',
            supported: [supply(voltage: 110, frequency: 60)],
            available: [grid('g1')],
          ),
        ),
      );
      expect(find.text('Incompatible'), findsOneWidget);
      expect(
        find.textContaining('Supported: AC 110 V 1ph 60 Hz ±10 %'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Available there: 230 V 1ph 50 Hz'),
        findsOneWidget,
      );
    });

    testWidgets('needs external supply', (tester) async {
      await check(tester, http(compat: (_) => report('needs_external_supply')));
      expect(
        find.textContaining('needs an external power supply'),
        findsOneWidget,
      );
    });

    testWidgets('not applicable', (tester) async {
      await check(tester, http(compat: (_) => report('not_applicable')));
      expect(find.textContaining('nothing to check'), findsOneWidget);
    });

    testWidgets('unknown grid', (tester) async {
      await check(tester, http(compat: (_) => report('unknown_grid')));
      expect(find.textContaining('no grid data for NL'), findsOneWidget);
    });

    testWidgets('a grid can be chosen and is sent', (tester) async {
      final h = http(grids: [grid('g1'), grid('g2', voltage: 400, phases: 3)]);
      await pumpTab(tester, h);
      await tester.enterText(find.byKey(const ValueKey('check-country')), 'NL');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('check-grid-NL-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('400 V 3ph 50 Hz').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Check'));
      await tester.pumpAndSettle();
      expect(h.queries.last['grid_id'], 'g2');
    });

    testWidgets('a country code of one letter is refused', (tester) async {
      final h = http();
      await pumpTab(tester, h);
      await tester.enterText(find.byKey(const ValueKey('check-country')), 'N');
      await tester.tap(find.widgetWithText(FilledButton, 'Check'));
      await tester.pumpAndSettle();
      expect(find.textContaining('two-letter country code'), findsOneWidget);
      expect(
        h.requests,
        isNot(contains('GET /api/v1/products/p1/power-compatibility')),
      );
    });
  });
}
