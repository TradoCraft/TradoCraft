import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/inventory/counts_page.dart';
import 'package:tradocraft_app/features/inventory/product_stock_screen.dart';
import 'package:tradocraft_app/features/inventory/stock_page.dart';
import 'package:tradocraft_app/features/inventory/warehouses_page.dart';
import 'package:tradocraft_app/features/products/product_form.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

const _read = ['inventory.read', 'products.read'];
const _write = ['inventory.read', 'inventory.write', 'products.read'];
const _admin = [
  'inventory.read',
  'inventory.write',
  'inventory.admin',
  'products.read',
];

Map<String, Object?> _warehouses() => {
  'id': 'w1',
  'code': 'WH1',
  'name': 'Main warehouse',
  'kind': 'warehouse',
  'active': true,
  'assigned_user_id': null,
  'assigned_user_name': null,
  'locations': [
    {
      'id': 'l1',
      'warehouse_id': 'w1',
      'code': 'MAIN',
      'name': '',
      'active': true,
    },
    {
      'id': 'l2',
      'warehouse_id': 'w1',
      'code': 'A-01',
      'name': 'Shelf A',
      'active': true,
    },
  ],
};

Map<String, Object?> _van() => {
  'id': 'w2',
  'code': 'VAN-1',
  'name': 'Van of Tom',
  'kind': 'van',
  'active': true,
  'assigned_user_id': 'u9',
  'assigned_user_name': 'Tom Technician',
  'locations': [
    {
      'id': 'l9',
      'warehouse_id': 'w2',
      'code': 'VAN',
      'name': '',
      'active': true,
    },
  ],
};

Map<String, Object?> _productStock({
  String onHand = '6.0000',
  String reserved = '2.0000',
  bool below = false,
}) => {
  'product_id': 'p1',
  'code': 'FRAME-A',
  'name': 'Frame assembly',
  'unit': 'pcs',
  'tracking': 'none',
  'barcode': '5412345678901',
  'reorder_min': '5.0000',
  'reorder_max': null,
  'lead_time_days': 14,
  'on_hand': onHand,
  'in_vans': '1.0000',
  'reserved': reserved,
  'available': '4.0000',
  'below_reorder': below,
};

Map<String, Object?> _product({String? cost}) => {
  'id': 'p1',
  'code': 'FRAME-A',
  'name': 'Frame assembly',
  'description': '',
  'unit': 'pcs',
  'product_type': 'manufactured',
  'vat_rate': '21',
  'tracking': 'none',
  'family_id': null,
  'family_code': null,
  'pricing_type': 'list',
  'active': true,
  'standard_cost': cost,
  'reorder_min': '5',
  'reorder_max': null,
  'lead_time_days': 14,
  'barcode': '5412345678901',
};

Map<String, Object?> _move({
  String id = 'm1',
  String kind = 'receipt',
  String reason = 'manual_receipt',
  String? reversedBy,
  String? reversedOf,
}) => {
  'id': id,
  'seq': 1,
  'product_id': 'p1',
  'product_code': 'FRAME-A',
  'product_name': 'Frame assembly',
  'unit': 'pcs',
  'quantity': '5.0000',
  'from_location_id': 'v1',
  'from_location': 'supplier',
  'to_location_id': 'l1',
  'to_location': 'WH1/MAIN',
  'lot_id': null,
  'lot_number': null,
  'serial_unit_id': null,
  'serial_number': null,
  'kind': kind,
  'reason': reason,
  'reference_type': null,
  'reference_id': null,
  'note': 'Delivery note 77',
  'entered_quantity': null,
  'entered_uom': null,
  'unit_cost': null,
  'reversed_of': reversedOf,
  'reversed_by': reversedBy,
  'occurred_at': '2026-11-06T09:00:00Z',
  'created_by_name': 'Stores',
  'created_at': '2026-11-06T09:00:00Z',
};

FakeHttp _http(
  List<String> perms, [
  Map<String, Object? Function(Object?)>? extra,
]) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/inventory/warehouses': (_) => [_warehouses(), _van()],
  'GET /api/v1/inventory/stock/products': (_) => {
    'items': [_productStock(below: true)],
    'total': 1,
  },
  'GET /api/v1/inventory/stock': (_) => {
    'items': [
      {
        'product_id': 'p1',
        'product_code': 'FRAME-A',
        'product_name': 'Frame assembly',
        'unit': 'pcs',
        'tracking': 'none',
        'warehouse_id': 'w1',
        'warehouse_kind': 'warehouse',
        'location_id': 'l1',
        'location': 'WH1/MAIN',
        'lot_id': null,
        'lot_number': null,
        'expiry_date': null,
        'on_hand': '6.0000',
        'reserved': '2.0000',
        'available': '4.0000',
      },
    ],
    'total': 1,
  },
  'GET /api/v1/inventory/reservations': (_) => [],
  'GET /api/v1/inventory/moves': (_) => {
    'items': [_move()],
    'total': 1,
  },
  'GET /api/v1/products/p1': (_) => _product(),
  'GET /api/v1/inventory/uoms': (_) => [
    {
      'code': 'pcs',
      'name': 'Pieces',
      'category': 'unit',
      'factor': '1',
      'active': true,
    },
  ],
  'GET /api/v1/inventory/products/p1/uoms': (_) => [],
  ...?extra,
});

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: '/stock/products/:id',
        builder: (_, _) => const Text('PRODUCT-STOCK'),
      ),
      GoRoute(path: '/stock/counts', builder: (_, _) => const Text('COUNTS')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the overview shows on hand, reserved and available per product',
    (tester) async {
      final http = _http(_read);
      await _pump(tester, http, const StockPage());
      expect(find.text('FRAME-A'), findsOneWidget);
      expect(find.text('6 pcs'), findsOneWidget);
      expect(find.text('Reserved'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      // Reading is enough to look; moving stock is not offered.
      expect(find.text('Receive'), findsNothing);
      expect(find.text('Issue'), findsNothing);
      expect(find.text('Transfer'), findsNothing);
    },
  );

  testWidgets('filters go to the server', (tester) async {
    final http = _http(_write);
    await _pump(tester, http, const StockPage());
    expect(find.text('Receive'), findsOneWidget);
    await tester.tap(find.text('Below reorder level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only in stock'));
    await tester.pumpAndSettle();
    final q = http.queries.last;
    expect(q['below_reorder'], true);
    expect(q['in_stock'], true);
  });

  testWidgets(
    'receiving from the product screen posts one move with a client id',
    (tester) async {
      final http = _http(_write, {
        'GET /api/v1/inventory/stock/products': (_) => {
          'items': [_productStock()],
          'total': 1,
        },
        'POST /api/v1/inventory/receipts': (_) => _move(),
      });
      await _pump(tester, http, const ProductStockScreen(id: 'p1'));
      expect(find.textContaining('Delivery note 77'), findsOneWidget);
      expect(
        find.text('Adjust'),
        findsNothing,
        reason: 'adjusting needs inventory.admin',
      );
      await tester.tap(find.text('Receive').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Location'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('WH1/A-01').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '5,5');
      await tester.tap(find.widgetWithText(FilledButton, 'Receive').last);
      await tester.pumpAndSettle();

      final body = http.bodies['POST /api/v1/inventory/receipts'] as Map;
      expect(body['product_id'], 'p1');
      expect(body['location_id'], 'l2');
      expect(body['quantity'], '5.5');
      expect(body['reason'], 'manual_receipt');
      expect(body['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      // The list is reloaded after the move.
      expect(
        http.requests.where((r) => r == 'GET /api/v1/inventory/moves').length,
        2,
      );
    },
  );

  testWidgets('a refused move shows the server message and stays open', (
    tester,
  ) async {
    final http = _http(_write);
    await _pump(tester, http, const ProductStockScreen(id: 'p1'));
    await tester.tap(find.text('Issue').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'From'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('WH1/MAIN').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '99');
    await tester.tap(find.widgetWithText(FilledButton, 'Issue').last);
    await tester.pumpAndSettle();
    // Unknown route: 404 from the fake server; the dialog reports it and does not close.
    expect(find.widgetWithText(FilledButton, 'Issue'), findsOneWidget);
    expect(
      find.textContaining('POST /api/v1/inventory/issues'),
      findsOneWidget,
    );
  });

  testWidgets('reversing a move is for administrators and sends a new id', (
    tester,
  ) async {
    final reversal = _move(id: 'm2', reason: 'reversal', reversedOf: 'm1');
    final http = _http(_admin, {
      'POST /api/v1/inventory/moves/m1/reverse': (_) => reversal,
    });
    await _pump(tester, http, const ProductStockScreen(id: 'p1'));
    expect(find.text('Adjust'), findsOneWidget);
    await tester.tap(find.byTooltip('Reverse'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'wrong product');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/inventory/moves/m1/reverse'] as Map;
    expect(body['note'], 'wrong product');
    expect(body['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  testWidgets('without inventory.admin there is no reverse button', (
    tester,
  ) async {
    await _pump(tester, _http(_write), const ProductStockScreen(id: 'p1'));
    expect(find.byTooltip('Reverse'), findsNothing);
  });

  testWidgets('warehouses and vans are listed; only the admin edits them', (
    tester,
  ) async {
    await _pump(tester, _http(_read), const WarehousesPage());
    expect(find.text('WH1 · Main warehouse'), findsOneWidget);
    expect(find.text('VAN-1 · Van of Tom'), findsOneWidget);
    expect(find.text('Assigned to: Tom Technician'), findsOneWidget);
    expect(find.text('A-01 · Shelf A'), findsOneWidget);
    expect(find.text('New warehouse'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('the admin adds a warehouse', (tester) async {
    final http = _http(_admin, {
      'POST /api/v1/inventory/warehouses': (_) => _warehouses(),
    });
    await _pump(tester, http, const WarehousesPage());
    await tester.tap(find.text('New warehouse'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Code'), 'WH2');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Overflow');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/inventory/warehouses'] as Map;
    expect(body['code'], 'WH2');
    expect(body['kind'], 'warehouse');
  });

  Map<String, Object?> count({
    String status = 'counting',
    int counted = 0,
    int moved = 0,
  }) => {
    'count': {
      'id': 'k1',
      'number': 'CNT-2026-00001',
      'warehouse_id': 'w1',
      'warehouse_code': 'WH1',
      'location_id': null,
      'location_code': null,
      'product_id': null,
      'status': status,
      'note': '',
      'created_by_name': 'Stores',
      'created_at': '2026-11-06T09:00:00Z',
      'closed_at': null,
      'line_count': 1,
      'counted_count': counted,
    },
    'lines': [
      {
        'id': 'cl1',
        'product_id': 'p1',
        'product_code': 'FRAME-A',
        'product_name': 'Frame assembly',
        'unit': 'pcs',
        'location_id': 'l1',
        'location': 'WH1/MAIN',
        'lot_id': null,
        'lot_number': null,
        'expected_quantity': '10.0000',
        'counted_quantity': counted == 0 ? null : '7.0000',
        'adjustment_move_id': null,
        'quantity_at_post': status == 'posted' ? '9.0000' : null,
        'difference_to_expected': counted == 0 ? null : '-3.0000',
      },
    ],
    'moved_during_count': status == 'posted' ? moved : 0,
  };

  testWidgets('counting shows the difference and sends the quantities', (
    tester,
  ) async {
    final http = _http(_write, {
      'GET /api/v1/inventory/counts/k1': (_) => count(),
      'PUT /api/v1/inventory/counts/k1/lines': (_) => count(counted: 1),
    });
    await _pump(tester, http, const CountScreen(id: 'k1'));
    expect(find.text('CNT-2026-00001'), findsOneWidget);
    expect(
      find.text('Post count'),
      findsNothing,
      reason: 'posting needs inventory.admin',
    );
    await tester.enterText(find.byType(TextField).last, '7');
    await tester.pump();
    expect(find.text('-3'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/inventory/counts/k1/lines'] as Map;
    final entry = (body['entries'] as List).single as Map;
    expect(entry['line_id'], 'cl1');
    expect(entry['counted_quantity'], '7');
  });

  testWidgets(
    'an open count warns that movements during the count are overwritten',
    (tester) async {
      final http = _http(_write, {
        'GET /api/v1/inventory/counts/k1': (_) => count(),
      });
      await _pump(tester, http, const CountScreen(id: 'k1'));
      expect(find.byKey(const ValueKey('count-warning')), findsOneWidget);
      expect(
        find.textContaining('Movements made while you count are overwritten'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a posted count says what moved while it was open', (
    tester,
  ) async {
    final http = _http(_admin, {
      'GET /api/v1/inventory/counts/k1': (_) =>
          count(status: 'posted', counted: 1, moved: 2),
    });
    await _pump(tester, http, const CountScreen(id: 'k1'));
    // No warning once it is closed; the lines that changed are reported.
    expect(find.byKey(const ValueKey('count-warning')), findsNothing);
    expect(find.byKey(const ValueKey('count-moved')), findsOneWidget);
    expect(
      find.textContaining('2 line(s) had stock movements'),
      findsOneWidget,
    );
    expect(find.byTooltip('Stock when posted: 9'), findsOneWidget);
  });

  testWidgets(
    'a reversal blocked by reservations can be forced by an administrator',
    (tester) async {
      final bodies = <Map<Object?, Object?>>[];
      final http = _http(_admin, {
        'POST /api/v1/inventory/moves/m1/reverse': (body) {
          bodies.add(body as Map<Object?, Object?>);
          return bodies.length == 1
              ? const FakeStatus(409, {
                  'error': 'conflict',
                  'message': '4 of FRAME-A at WH1/MAIN is reserved for orders; only 1 can be taken',
                })
              : _move(id: 'm2', reason: 'reversal', reversedOf: 'm1');
        },
      });
      await _pump(tester, http, const ProductStockScreen(id: 'p1'));
      await tester.tap(find.byTooltip('Reverse'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'supplier error');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // The server's reason is shown and nothing was forced yet.
      expect(find.textContaining('is reserved for orders'), findsOneWidget);
      expect(bodies.single['force'], anyOf(isNull, false));
      await tester.tap(find.byKey(const ValueKey('reverse-anyway')));
      await tester.pumpAndSettle();
      expect(bodies.length, 2);
      expect(bodies[1]['force'], true);
      expect(
        bodies[1]['id'],
        bodies[0]['id'],
        reason: 'the same move id: a retry, not a second reversal',
      );
    },
  );

  testWidgets('the admin posts a count after confirming', (tester) async {
    final http = _http(_admin, {
      'GET /api/v1/inventory/counts/k1': (_) => count(counted: 1),
      'PUT /api/v1/inventory/counts/k1/lines': (_) => count(counted: 1),
      'POST /api/v1/inventory/counts/k1/post': (_) =>
          count(status: 'posted', counted: 1),
    });
    await _pump(tester, http, const CountScreen(id: 'k1'));
    await tester.tap(find.widgetWithText(FilledButton, 'Post count'));
    await tester.pumpAndSettle();
    expect(
      http.requests,
      isNot(contains('POST /api/v1/inventory/counts/k1/post')),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Post count').last);
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/inventory/counts/k1/post'));
    // A posted count is read-only.
    expect(find.widgetWithText(FilledButton, 'Post count'), findsNothing);
    expect(find.text('Posted'), findsOneWidget);
  });

  testWidgets('the product form offers cost only with inventory.cost', (
    tester,
  ) async {
    for (final withCost in [false, true]) {
      final http = _http(
        ['products.read', 'products.write', if (withCost) 'inventory.cost'],
        {'PUT /api/v1/products/p1': (_) => _product(cost: '812.5000')},
      );
      await _pump(
        tester,
        http,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showProductForm(
              context,
              product: Product.fromJson(
                _product(cost: withCost ? '812.5000' : null),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text('Standard cost'),
        withCost ? findsOneWidget : findsNothing,
      );
      expect(find.text('Barcode'), findsOneWidget);
      expect(find.text('Reorder minimum'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/products/p1'] as Map;
      expect(body['standard_cost'], withCost ? '812.5' : isNull);
      expect(body['reorder_min'], '5');
      expect(body['lead_time_days'], 14);
      expect(body['barcode'], '5412345678901');
    }
  });
}
