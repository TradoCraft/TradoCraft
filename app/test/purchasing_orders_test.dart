import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/purchasing/order_screen.dart';
import 'package:tradocraft_app/features/purchasing/purchasing_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _line({
  int n = 1,
  String product = 'p1',
  String qty = '10.0000',
  String received = '0.0000',
  String price = '12.5000',
}) => {
  'id': 'l$n',
  'purchase_order_id': 'po1',
  'line_number': n,
  'product_id': product,
  'product_code': 'MOT-$n',
  'product_name': 'Motor $n',
  'supplier_product_code': 'AC-77',
  'description': '',
  'quantity': qty,
  'quantity_received': received,
  'unit_price': price,
  'line_total': '125.00',
  'created_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _po({
  String id = 'po1',
  String number = 'PO2027-00001',
  String status = 'draft',
  String supplier = 'Acme Motors',
  String notes = 'Rush',
  List<Map<String, Object?>>? lines,
}) => {
  'id': id,
  'company_id': 'co',
  'number': number,
  'supplier_id': 's1',
  'supplier_name': supplier,
  'status': status,
  'order_date': '2027-01-05',
  'expected_delivery_date': '2027-01-20',
  'currency': 'EUR',
  'subtotal': '125.00',
  'tax_total': '0.00',
  'total': '125.00',
  'notes': notes,
  'created_by_user_id': 'u1',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
  'lines': lines ?? [_line()],
};

Map<String, Object?> _supplier() => {
  'id': 's1',
  'company_id': 'co',
  'name': 'Acme Motors',
  'code': 'SUP-001',
  'country': 'DE',
  'currency': 'EUR',
  'email': '',
  'phone': '',
  'contact_person': '',
  'payment_terms_days': 30,
  'tax_id': '',
  'active': true,
  'notes': '',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _price({
  String product = 'p1',
  String code = 'MOT-1',
  String name = 'Motor 1kW',
  String sku = 'AC-77',
  String price = '12.5000',
  String moq = '1.0000',
}) => {
  'id': 'sp-$product',
  'company_id': 'co',
  'supplier_id': 's1',
  'supplier_name': 'Acme Motors',
  'product_id': product,
  'product_code': code,
  'product_name': name,
  'supplier_product_code': sku,
  'supplier_product_name': 'Acme motor',
  'currency': 'EUR',
  'unit_price': price,
  'moq': moq,
  'lead_time_days': 14,
  'is_preferred': true,
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _productList() => {
  'total': 1,
  'items': [
    {
      'id': 'p1',
      'code': 'MOT-1',
      'name': 'Motor 1kW',
      'description': '',
      'active': true,
      'pricing_type': 'fixed',
      'product_type': 'purchased',
      'tracking': 'none',
      'unit': 'pcs',
      'vat_rate': '21',
    },
  ],
};

const _wide = Size(1400, 1600);

Future<void> _app(
  WidgetTester tester,
  FakeHttp http, {
  required String initial,
}) async {
  tester.view.physicalSize = _wide;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/purchasing',
        builder: (_, _) => const Scaffold(body: PurchasingPage()),
      ),
      GoRoute(
        path: '/purchase-orders/:id',
        builder: (_, s) =>
            Scaffold(body: PurchaseOrderScreen(id: s.pathParameters['id']!)),
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

Future<void> _openOrdersSegment(WidgetTester tester) async {
  await tester.tap(find.text('Purchase orders'));
  await tester.pumpAndSettle();
}

Map<String, Object? Function(Object?)> _detailRoutes(
  List<String> perms,
  Map<String, Object?> Function() current,
) => {
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/purchase-orders/po1': (_) => current(),
  'GET /api/v1/suppliers/s1/products': (_) => [_price()],
};

void main() {
  testWidgets('lists orders with text status, filters and search', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/suppliers': (_) => [_supplier()],
      'GET /api/v1/purchase-orders': (_) => [
        _po(),
        _po(
          id: 'po2',
          number: 'PO2027-00002',
          status: 'sent',
          supplier: 'Bolt',
        ),
      ],
    });
    await _app(tester, http, initial: '/purchasing');
    await _openOrdersSegment(tester);
    expect(find.text('PO2027-00001'), findsOneWidget);
    expect(find.byKey(const ValueKey('po-status-draft')), findsOneWidget);
    expect(find.byKey(const ValueKey('po-status-sent')), findsOneWidget);
    expect(find.text('New purchase order'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('po-filter-sent')));
    await tester.pumpAndSettle();
    expect(http.queries.last['status'], 'sent');

    await tester.tap(find.byKey(const ValueKey('po-filter-supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Motors').last);
    await tester.pumpAndSettle();
    expect(http.queries.last['supplier_id'], 's1');
    expect(http.queries.last['status'], 'sent');

    await tester.tap(find.byKey(const ValueKey('po-filter-all')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'bolt');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('PO2027-00001'), findsNothing);
    expect(find.text('PO2027-00002'), findsOneWidget);
  });

  testWidgets('shows the empty and the error state with retry', (tester) async {
    final empty = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/suppliers': (_) => <Object?>[],
      'GET /api/v1/purchase-orders': (_) => <Object?>[],
    });
    await _app(tester, empty, initial: '/purchasing');
    await _openOrdersSegment(tester);
    expect(find.text('No purchase orders found.'), findsOneWidget);

    final failing = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/suppliers': (_) => <Object?>[],
      'GET /api/v1/purchase-orders': (_) =>
          const FakeStatus(500, {'error': 'x', 'message': 'Database down'}),
    });
    await _app(tester, failing, initial: '/purchasing');
    await _openOrdersSegment(tester);
    expect(find.text('Database down'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the orders segment needs purchasing.read', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['customers.read']),
    });
    await _app(tester, http, initial: '/purchasing');
    expect(find.text('Purchase orders'), findsNothing);
    expect(find.byKey(const ValueKey('purchasing-segments')), findsNothing);
  });

  testWidgets('creates a draft with defaults from the price list', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers': (_) => [_supplier()],
      'GET /api/v1/purchase-orders': (_) => <Object?>[],
      'GET /api/v1/suppliers/s1/products': (_) => [_price()],
      'GET /api/v1/products': (_) => _productList(),
      'POST /api/v1/purchase-orders': (_) => _po(id: 'po9'),
      'GET /api/v1/purchase-orders/po9': (_) => _po(id: 'po9'),
    });
    await _app(tester, http, initial: '/purchasing');
    await _openOrdersSegment(tester);
    await tester.tap(find.text('New purchase order'));
    await tester.pumpAndSettle();

    // Validation: supplier, then product, then quantity.
    await tester.tap(find.byKey(const ValueKey('po-save')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a supplier.'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('po-supplier')),
        matching: find.byType(TextField),
      ),
      'acme',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP-001 · Acme Motors').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('po-save')));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one line.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('po-goods-check-p1')));
    await tester.pumpAndSettle();
    // Price comes from the price list, quantity from the tick; lead time sets the date.
    expect(find.textContaining('Expected delivery:'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('po-goods-qty-p1')), '0');
    await tester.tap(find.byKey(const ValueKey('po-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('greater than zero'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('po-goods-qty-p1')), '10');
    await tester.enterText(find.byKey(const ValueKey('po-notes')), 'Rush');
    await tester.tap(find.byKey(const ValueKey('po-save')));
    await tester.pumpAndSettle();

    final body = http.bodies['POST /api/v1/purchase-orders']! as Map;
    expect(body['supplier_id'], 's1');
    expect(body['notes'], 'Rush');
    expect(body['expected_delivery_date'], isNotNull);
    final line = (body['lines']! as List).single as Map;
    expect(line['product_id'], 'p1');
    expect(line['quantity'], '10');
    expect(line['unit_price'], '12.5');
    expect(line['supplier_product_code'], 'AC-77');
    // The new order opens.
    expect(http.requests, contains('GET /api/v1/purchase-orders/po9'));
    expect(find.text('PO2027-00001'), findsOneWidget);
  });

  testWidgets('a create conflict stays in the dialog', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers': (_) => [_supplier()],
      'GET /api/v1/purchase-orders': (_) => <Object?>[],
      'GET /api/v1/suppliers/s1/products': (_) => [_price()],
      'GET /api/v1/products': (_) => _productList(),
      'POST /api/v1/purchase-orders': (_) => const FakeStatus(422, {
        'error': 'validation',
        'message': 'line 1: product not found',
      }),
    });
    await _app(tester, http, initial: '/purchasing');
    await _openOrdersSegment(tester);
    await tester.tap(find.text('New purchase order'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('po-supplier')),
        matching: find.byType(TextField),
      ),
      'acme',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP-001 · Acme Motors').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('po-goods-check-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('po-save')));
    await tester.pumpAndSettle();
    expect(find.text('line 1: product not found'), findsOneWidget);
    expect(find.byKey(const ValueKey('po-save')), findsOneWidget);
  });

  testWidgets('draft detail shows lines and received quantities', (
    tester,
  ) async {
    final http = FakeHttp(
      _detailRoutes([
        'purchasing.read',
      ], () => _po(lines: [_line(received: '4.0000')])),
    );
    await _app(tester, http, initial: '/purchase-orders/po1');
    expect(find.text('PO2027-00001'), findsOneWidget);
    expect(find.byKey(const ValueKey('po-status-draft')), findsOneWidget);
    expect(find.text('Acme Motors'), findsOneWidget);
    expect(find.text('MOT-1 · Motor 1'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('po-received-1'))).data,
      '4',
    );
    // Read-only without rights.
    expect(find.byKey(const ValueKey('po-edit')), findsNothing);
    expect(find.byKey(const ValueKey('po-approve')), findsNothing);
    expect(find.byKey(const ValueKey('po-cancel')), findsNothing);
  });

  testWidgets('edits a draft', (tester) async {
    var current = _po();
    final http = FakeHttp({
      ..._detailRoutes(['purchasing.read', 'purchasing.write'], () => current),
      'PUT /api/v1/purchase-orders/po1': (b) {
        current = _po(notes: (b! as Map)['notes'] as String);
        return current;
      },
    });
    await _app(tester, http, initial: '/purchase-orders/po1');
    await tester.tap(find.byKey(const ValueKey('po-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('po-notes')), 'Urgent');
    await tester.enterText(find.byKey(const ValueKey('po-line-qty-0')), '12');
    await tester.tap(find.byKey(const ValueKey('po-save')));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/purchase-orders/po1']! as Map;
    expect(body['notes'], 'Urgent');
    final line = (body['lines']! as List).single as Map;
    expect(line['product_id'], 'p1');
    expect(line['quantity'], '12');
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.byKey(const ValueKey('po-save')), findsNothing);
  });

  testWidgets('approve is hidden without the approve right', (tester) async {
    final http = FakeHttp(
      _detailRoutes(['purchasing.read', 'purchasing.write'], () => _po()),
    );
    await _app(tester, http, initial: '/purchase-orders/po1');
    expect(find.byKey(const ValueKey('po-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('po-approve')), findsNothing);
  });

  testWidgets('approve, send and cancel follow the lifecycle', (tester) async {
    var current = _po();
    final http = FakeHttp({
      ..._detailRoutes([
        'purchasing.read',
        'purchasing.write',
        'purchasing.approve',
      ], () => current),
      'POST /api/v1/purchase-orders/po1/approve': (_) =>
          current = _po(status: 'approved'),
      'POST /api/v1/purchase-orders/po1/send': (_) =>
          current = _po(status: 'sent'),
      'POST /api/v1/purchase-orders/po1/cancel': (_) =>
          current = _po(status: 'cancelled'),
    });
    await _app(tester, http, initial: '/purchase-orders/po1');
    expect(find.byKey(const ValueKey('po-send')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('po-approve')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('po-status-approved')), findsOneWidget);
    expect(find.byKey(const ValueKey('po-approve')), findsNothing);
    expect(find.byKey(const ValueKey('po-edit')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('po-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('po-status-sent')), findsOneWidget);
    expect(find.byKey(const ValueKey('po-send')), findsNothing);

    // Cancel asks first; keeping the order sends nothing.
    await tester.tap(find.byKey(const ValueKey('po-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Cancel purchase order PO2027-00001?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('po-cancel-keep')));
    await tester.pumpAndSettle();
    expect(
      http.requests,
      isNot(contains('POST /api/v1/purchase-orders/po1/cancel')),
    );
    await tester.tap(find.byKey(const ValueKey('po-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('po-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('po-status-cancelled')), findsOneWidget);
    expect(find.byKey(const ValueKey('po-cancel')), findsNothing);
  });

  testWidgets('received orders are read-only; conflicts show a banner', (
    tester,
  ) async {
    final received = FakeHttp(
      _detailRoutes([
        'purchasing.read',
        'purchasing.write',
        'purchasing.approve',
      ], () => _po(status: 'partially_received')),
    );
    await _app(tester, received, initial: '/purchase-orders/po1');
    expect(
      find.byKey(const ValueKey('po-status-partially_received')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('po-cancel')), findsNothing);
    expect(find.byKey(const ValueKey('po-approve')), findsNothing);

    final http = FakeHttp({
      ..._detailRoutes([
        'purchasing.read',
        'purchasing.write',
        'purchasing.approve',
      ], () => _po()),
      'POST /api/v1/purchase-orders/po1/approve': (_) => const FakeStatus(409, {
        'error': 'conflict',
        'message': 'only draft purchase orders can be approved',
      }),
    });
    await _app(tester, http, initial: '/purchase-orders/po1');
    await tester.tap(find.byKey(const ValueKey('po-approve')));
    await tester.pumpAndSettle();
    expect(
      find.text('only draft purchase orders can be approved'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('po-status-draft')), findsOneWidget);
  });

  testWidgets('detail load error offers retry', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/purchase-orders/po1': (_) =>
          const FakeStatus(404, {'error': 'nf', 'message': 'Not found'}),
    });
    await _app(tester, http, initial: '/purchase-orders/po1');
    expect(find.text('Not found'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tab label falls back to the kind', (tester) async {
    late String label;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            label = tabLabel(
              AppLocalizations.of(context),
              const WorkTab(id: 1, location: '/purchase-orders/abcdef123456'),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(label, 'Purchase order abcdef12');
  });
}
