import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/purchasing/order_screen.dart';
import 'package:tradocraft_app/features/purchasing/receipt_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _line({
  int n = 1,
  String product = 'p1',
  String qty = '10.0000',
  String received = '0.0000',
}) => {
  'id': 'l$n',
  'purchase_order_id': 'po1',
  'line_number': n,
  'product_id': product,
  'product_code': 'MOT-$n',
  'product_name': 'Motor $n',
  'supplier_product_code': '',
  'description': '',
  'quantity': qty,
  'quantity_received': received,
  'unit_price': '12.5000',
  'line_total': '125.00',
  'created_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _po({
  String status = 'sent',
  List<Map<String, Object?>>? lines,
}) => {
  'id': 'po1',
  'company_id': 'co',
  'number': 'PO2027-00001',
  'supplier_id': 's1',
  'supplier_name': 'Acme Motors',
  'status': status,
  'order_date': '2027-01-05',
  'expected_delivery_date': '2027-01-20',
  'currency': 'EUR',
  'subtotal': '125.00',
  'tax_total': '0.00',
  'total': '125.00',
  'notes': '',
  'created_by_user_id': 'u1',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
  'lines': lines ?? [_line()],
};

Map<String, Object?> _product(String id, String tracking) => {
  'id': id,
  'company_id': 'co',
  'code': 'MOT',
  'name': 'Motor',
  'description': '',
  'active': true,
  'pricing_type': 'fixed',
  'product_type': 'purchased',
  'tracking': tracking,
  'unit': 'pcs',
  'vat_rate': '21',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _warehouse() => {
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
  ],
};

Map<String, Object?> _summary() => {
  'id': 'gr1',
  'company_id': 'co',
  'number': 'GR2027-00001',
  'purchase_order_id': 'po1',
  'purchase_order_number': 'PO2027-00001',
  'supplier_name': 'Acme Motors',
  'warehouse_id': 'w1',
  'location_id': 'l1',
  'received_date': '2027-01-10T10:00:00Z',
  'received_by_user_id': 'u1',
  'carrier': 'DHL',
  'tracking_number': 'T-1',
  'supplier_delivery_note': 'DN-9',
  'notes': 'Dented box',
  'created_at': '2027-01-10T10:00:00Z',
};

Map<String, Object?> _receipt() => {
  ..._summary(),
  'lines': [
    {
      'id': 'grl1',
      'goods_receipt_id': 'gr1',
      'po_line_id': 'l1',
      'product_id': 'p1',
      'product_code': 'MOT-1',
      'product_name': 'Motor 1',
      'quantity_received': '4.0000',
      'lot_number': 'LOT-7',
      'created_at': '2027-01-10T10:00:00Z',
    },
  ],
};

const _recv = ['purchasing.read', 'purchasing.receipt'];

Map<String, Object? Function(Object?)> _routes(
  List<String> perms,
  Map<String, Object?> Function() po, {
  String tracking = 'none',
  List<Object?>? receipts,
}) => {
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/purchase-orders/po1': (_) => po(),
  'GET /api/v1/purchase-orders/po1/receipts': (_) => receipts ?? <Object?>[],
  'GET /api/v1/products/p1': (_) => _product('p1', tracking),
  'GET /api/v1/inventory/warehouses': (_) => [_warehouse()],
};

Future<void> _app(
  WidgetTester tester,
  FakeHttp http, {
  String initial = '/purchase-orders/po1',
}) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/purchase-orders/:id',
        builder: (_, s) =>
            Scaffold(body: PurchaseOrderScreen(id: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/goods-receipts/:id',
        builder: (_, s) =>
            Scaffold(body: GoodsReceiptScreen(id: s.pathParameters['id']!)),
      ),
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

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('po-receive')));
  await tester.pumpAndSettle();
  // Pick the only destination location.
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('WH1/MAIN').last);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('receive-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the receive button follows status and permission', (
    tester,
  ) async {
    for (final status in ['approved', 'sent', 'partially_received']) {
      await _app(tester, FakeHttp(_routes(_recv, () => _po(status: status))));
      expect(
        find.byKey(const ValueKey('po-receive')),
        findsOneWidget,
        reason: status,
      );
    }
    for (final status in ['draft', 'received', 'cancelled']) {
      await _app(tester, FakeHttp(_routes(_recv, () => _po(status: status))));
      expect(
        find.byKey(const ValueKey('po-receive')),
        findsNothing,
        reason: status,
      );
    }
    await _app(
      tester,
      FakeHttp(_routes(['purchasing.read', 'purchasing.write'], () => _po())),
    );
    expect(find.byKey(const ValueKey('po-receive')), findsNothing);
  });

  testWidgets('defaults to the remaining quantity and posts the receipt', (
    tester,
  ) async {
    var status = 'sent';
    var received = '0.0000';
    final http = FakeHttp({
      ..._routes(
        _recv,
        () => _po(
          status: status,
          lines: [
            _line(received: received),
            _line(n: 2, qty: '3', received: '3'),
          ],
        ),
        receipts: [_summary()],
      ),
      'GET /api/v1/goods-receipts/gr1': (_) => _receipt(),
      'POST /api/v1/purchase-orders/po1/receipts': (_) {
        status = 'partially_received';
        received = '6.0000';
        return _receipt();
      },
    });
    await _app(tester, http);
    await _openDialog(tester);
    // Fully received lines are not offered; the other defaults to what is open.
    expect(find.byKey(const ValueKey('receive-qty-2')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('receive-qty-1')))
          .controller!
          .text,
      '10',
    );
    await tester.enterText(find.byKey(const ValueKey('receive-qty-1')), '6');
    await tester.enterText(
      find.byKey(const ValueKey('receive-carrier')),
      'DHL',
    );
    await tester.enterText(find.byKey(const ValueKey('receive-notes')), 'ok');
    await _submit(tester);

    final body =
        http.bodies['POST /api/v1/purchase-orders/po1/receipts']!
            as Map<String, dynamic>;
    expect(body['warehouse_id'], 'w1');
    expect(body['location_id'], 'l1');
    expect(body['carrier'], 'DHL');
    expect(body['notes'], 'ok');
    expect(body['tracking_number'], isNull);
    final lines = body['lines'] as List;
    expect(lines, hasLength(1));
    expect(lines.first['po_line_id'], 'l1');
    expect(lines.first['quantity'], '6');

    // The order was reloaded: new status and received quantity, plus the open-receipt action.
    expect(find.byKey(const ValueKey('po-received-1')), findsOneWidget);
    expect(find.text('6'), findsWidgets);
    expect(find.text('Goods receipt GR2027-00001 booked.'), findsOneWidget);
    expect(find.byKey(const ValueKey('po-receipt-gr1')), findsOneWidget);
    await tester.tap(find.text('Open receipt'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gr-open-po')), findsOneWidget);
  });

  testWidgets('validates quantities before posting', (tester) async {
    final http = FakeHttp(
      _routes(_recv, () => _po(lines: [_line(received: '4')])),
    );
    await _app(tester, http);
    await _openDialog(tester);
    final qty = find.byKey(const ValueKey('receive-qty-1'));
    await tester.enterText(qty, '7');
    await _submit(tester);
    expect(find.textContaining('between 0 and 6'), findsOneWidget);
    await tester.enterText(qty, '0');
    await _submit(tester);
    expect(
      find.text('Enter a quantity for at least one line.'),
      findsOneWidget,
    );
    await tester.enterText(qty, 'abc');
    await _submit(tester);
    expect(find.textContaining('between 0 and 6'), findsOneWidget);
    expect(http.requests.where((r) => r.startsWith('POST')), isEmpty);
  });

  testWidgets('needs a destination location', (tester) async {
    final http = FakeHttp({
      ..._routes(_recv, () => _po()),
      'GET /api/v1/inventory/warehouses': (_) => [
        _warehouse(),
        {
          ..._warehouse(),
          'id': 'w2',
          'code': 'WH2',
          'locations': [
            {
              'id': 'l2',
              'warehouse_id': 'w2',
              'code': 'MAIN',
              'name': '',
              'active': true,
            },
          ],
        },
      ],
    });
    await _app(tester, http);
    await tester.tap(find.byKey(const ValueKey('po-receive')));
    await tester.pumpAndSettle();
    await _submit(tester);
    expect(find.text('Choose a destination location.'), findsOneWidget);
  });

  testWidgets('preselects the only destination location', (tester) async {
    final http = FakeHttp({
      ..._routes(_recv, () => _po(), receipts: [_summary()]),
      'GET /api/v1/goods-receipts/gr1': (_) => _receipt(),
      'POST /api/v1/purchase-orders/po1/receipts': (_) => _receipt(),
    });
    await _app(tester, http);
    await tester.tap(find.byKey(const ValueKey('po-receive')));
    await tester.pumpAndSettle();
    await _submit(tester);
    final body =
        http.bodies['POST /api/v1/purchase-orders/po1/receipts']!
            as Map<String, dynamic>;
    expect(body['location_id'], 'l1');
  });

  testWidgets('says how to create a location when none exists', (tester) async {
    final http = FakeHttp({
      ..._routes(_recv, () => _po()),
      'GET /api/v1/inventory/warehouses': (_) => <Object?>[],
    });
    await _app(tester, http);
    await tester.tap(find.byKey(const ValueKey('po-receive')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('no-locations-hint')), findsOneWidget);
  });

  testWidgets('lot-tracked products need a lot number', (tester) async {
    final http = FakeHttp({
      ..._routes(_recv, () => _po(), tracking: 'lot'),
      'POST /api/v1/purchase-orders/po1/receipts': (_) => _receipt(),
    });
    await _app(tester, http);
    await _openDialog(tester);
    expect(find.byKey(const ValueKey('receive-lot-1')), findsOneWidget);
    await _submit(tester);
    expect(find.text('MOT-1: enter a lot number.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('receive-lot-1')),
      'LOT-7',
    );
    await _submit(tester);
    final body =
        http.bodies['POST /api/v1/purchase-orders/po1/receipts']!
            as Map<String, dynamic>;
    expect((body['lines'] as List).first['lot_number'], 'LOT-7');
  });

  testWidgets('serial-tracked products need one serial number per unit', (
    tester,
  ) async {
    final http = FakeHttp({
      ..._routes(_recv, () => _po(), tracking: 'serial'),
      'POST /api/v1/purchase-orders/po1/receipts': (_) => _receipt(),
    });
    await _app(tester, http);
    await _openDialog(tester);
    final qty = find.byKey(const ValueKey('receive-qty-1'));
    final serials = find.byKey(const ValueKey('receive-serials-1'));
    await tester.enterText(qty, '2');
    await tester.enterText(serials, 'A1');
    await _submit(tester);
    expect(find.textContaining('exactly 2 different serial'), findsOneWidget);
    await tester.enterText(serials, 'A1\nA1');
    await _submit(tester);
    expect(find.textContaining('exactly 2 different serial'), findsOneWidget);
    await tester.enterText(qty, '1.5');
    await _submit(tester);
    expect(find.textContaining('whole number'), findsOneWidget);
    await tester.enterText(qty, '2');
    await tester.enterText(serials, 'A1\nA2');
    await _submit(tester);
    final body =
        http.bodies['POST /api/v1/purchase-orders/po1/receipts']!
            as Map<String, dynamic>;
    expect((body['lines'] as List).first['serial_numbers'], ['A1', 'A2']);
  });

  testWidgets('shows a conflict from the server and keeps the dialog', (
    tester,
  ) async {
    final http = FakeHttp({
      ..._routes(_recv, () => _po()),
      'POST /api/v1/purchase-orders/po1/receipts': (_) => const FakeStatus(
        409,
        {'error': 'conflict', 'message': 'order was cancelled'},
      ),
    });
    await _app(tester, http);
    await _openDialog(tester);
    await _submit(tester);
    expect(find.byKey(const ValueKey('receive-error')), findsOneWidget);
    expect(find.textContaining('order was cancelled'), findsOneWidget);
    expect(find.byKey(const ValueKey('receive-submit')), findsOneWidget);
  });

  testWidgets('the receipt screen shows header, lines and links to the order', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/goods-receipts/gr1': (_) => _receipt(),
      ..._routes(['purchasing.read'], () => _po()),
    });
    await _app(tester, http, initial: '/goods-receipts/gr1');
    expect(find.text('GR2027-00001'), findsOneWidget);
    expect(find.text('Acme Motors'), findsOneWidget);
    expect(find.text('DHL'), findsOneWidget);
    expect(find.text('DN-9'), findsOneWidget);
    expect(find.text('Dented box'), findsOneWidget);
    expect(find.text('LOT-7'), findsOneWidget);
    expect(find.text('MOT-1 · Motor 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gr-open-po')));
    await tester.pumpAndSettle();
    expect(find.text('PO2027-00001'), findsWidgets);
    expect(find.byKey(const ValueKey('po-status-sent')), findsOneWidget);
  });

  testWidgets('a failed receipt load can be retried', (tester) async {
    var fail = true;
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/goods-receipts/gr1': (_) => fail
          ? const FakeStatus(500, {'error': 'internal', 'message': 'boom'})
          : _receipt(),
    });
    await _app(tester, http, initial: '/goods-receipts/gr1');
    expect(find.byKey(const ValueKey('gr-error')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('gr-retry')));
    await tester.pumpAndSettle();
    expect(find.text('GR2027-00001'), findsOneWidget);
  });

  testWidgets('tab label of a receipt', (tester) async {
    late AppLocalizations l;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            l = AppLocalizations.of(c);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      tabLabel(
        l,
        const WorkTab(id: 1, location: '/goods-receipts/abcdef123456'),
      ),
      'Goods receipt abcdef12',
    );
    expect(
      tabLabel(
        l,
        const WorkTab(
          id: 1,
          location: '/goods-receipts/x',
          title: 'GR2027-00001',
        ),
      ),
      'GR2027-00001',
    );
  });
}
