import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/detail_routes.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/purchasing/purchasing_page.dart';
import 'package:tradocraft_app/features/purchasing/supplier_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _supplier({
  String id = 's1',
  String name = 'Acme Motors',
  String code = 'SUP-001',
  bool active = true,
}) => {
  'id': id,
  'company_id': 'co',
  'name': name,
  'code': code,
  'country': 'DE',
  'currency': 'EUR',
  'email': 'sales@acme.example',
  'phone': '+49 1',
  'contact_person': 'Ines Acme',
  'payment_terms_days': 45,
  'tax_id': 'DE123',
  'active': active,
  'notes': 'Reliable',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _price({
  String productId = 'p1',
  String code = 'MOT-1',
  String name = 'Motor 1kW',
  String price = '12.5000',
}) => {
  'id': 'sp-$productId',
  'company_id': 'co',
  'supplier_id': 's1',
  'supplier_name': 'Acme Motors',
  'product_id': productId,
  'product_code': code,
  'product_name': name,
  'supplier_product_code': 'AC-77',
  'supplier_product_name': 'Acme motor',
  'currency': 'EUR',
  'unit_price': price,
  'moq': '10.0000',
  'lead_time_days': 14,
  'is_preferred': true,
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
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
        path: '/suppliers/:id',
        builder: (_, s) =>
            Scaffold(body: SupplierScreen(id: s.pathParameters['id']!)),
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

void main() {
  testWidgets('lists suppliers (first segment), filters', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/suppliers': (_) => [
        _supplier(),
        _supplier(id: 's2', name: 'Bolt Works', code: 'SUP-002'),
      ],
    });
    await _app(tester, http, initial: '/purchasing');
    expect(find.text('Acme Motors'), findsOneWidget);
    expect(find.text('Bolt Works'), findsOneWidget);
    expect(find.text('45 days'), findsNWidgets(2));
    // Suppliers and purchase orders are both segments; no create button without the write right.
    expect(find.byKey(const ValueKey('purchasing-segments')), findsOneWidget);
    expect(find.text('New supplier'), findsNothing);
    expect(http.queries.last['active_only'], true);

    await tester.enterText(find.byType(TextField).first, 'bolt');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Acme Motors'), findsNothing);
    expect(find.text('Bolt Works'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('suppliers-active-only')));
    await tester.pumpAndSettle();
    expect(http.queries.last['active_only'], false);
  });

  testWidgets('shows the empty and the error state', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/suppliers': (_) => <Object?>[],
    });
    await _app(tester, http, initial: '/purchasing');
    expect(find.text('No suppliers found.'), findsOneWidget);

    final failing = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/suppliers': (_) =>
          const FakeStatus(500, {'error': 'x', 'message': 'Database down'}),
    });
    await _app(tester, failing, initial: '/purchasing');
    expect(find.text('Database down'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the create dialog shows the code before the name', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers': (_) => <Object?>[],
    });
    await _app(tester, http, initial: '/purchasing');
    await tester.tap(find.text('New supplier'));
    await tester.pumpAndSettle();
    final code = tester.getTopLeft(find.byKey(const ValueKey('supplier-code')));
    final name = tester.getTopLeft(find.byKey(const ValueKey('supplier-name')));
    expect(code.dy == name.dy ? code.dx < name.dx : code.dy < name.dy, isTrue);
  });

  testWidgets('creates a supplier and opens it', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers': (_) => <Object?>[],
      'POST /api/v1/suppliers': (b) =>
          _supplier(id: 's9', name: (b! as Map)['name'] as String),
      'GET /api/v1/suppliers/s9': (_) => _supplier(id: 's9', name: 'Zeta'),
      'GET /api/v1/suppliers/s9/products': (_) => <Object?>[],
    });
    await _app(tester, http, initial: '/purchasing');
    await tester.tap(find.text('New supplier'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('supplier-save')));
    await tester.pumpAndSettle();
    expect(find.text('The name is required.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('supplier-name')), 'Zeta');
    await tester.enterText(find.byKey(const ValueKey('supplier-terms')), '60');
    await tester.tap(find.byKey(const ValueKey('supplier-save')));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/suppliers']! as Map;
    expect(body['name'], 'Zeta');
    expect(body['country'], 'BE');
    expect(body['payment_terms_days'], 60);
    // The new supplier opens.
    expect(http.requests, contains('GET /api/v1/suppliers/s9'));
    expect(find.text('Zeta'), findsOneWidget);
    expect(find.text('No products on this price list yet.'), findsOneWidget);
  });

  testWidgets('a create error stays in the dialog', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers': (_) => <Object?>[],
      'POST /api/v1/suppliers': (_) => const FakeStatus(409, {
        'error': 'conflict',
        'message': 'Code in use',
      }),
    });
    await _app(tester, http, initial: '/purchasing');
    await tester.tap(find.text('New supplier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('supplier-name')), 'Dup');
    await tester.tap(find.byKey(const ValueKey('supplier-save')));
    await tester.pumpAndSettle();
    expect(find.text('Code in use'), findsOneWidget);
    expect(find.byKey(const ValueKey('supplier-name')), findsOneWidget);
  });

  testWidgets('edits a supplier', (tester) async {
    var current = _supplier();
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers/s1': (_) => current,
      'GET /api/v1/suppliers/s1/products': (_) => [_price()],
      'PUT /api/v1/suppliers/s1': (b) {
        current = _supplier(name: (b! as Map)['name'] as String);
        return current;
      },
    });
    await _app(tester, http, initial: '/suppliers/s1');
    expect(find.text('Acme Motors'), findsOneWidget);
    expect(find.text('DE123'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('supplier-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('supplier-name')),
      'Acme Drives',
    );
    await tester.tap(find.byKey(const ValueKey('supplier-save')));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/suppliers/s1']! as Map;
    expect(body['name'], 'Acme Drives');
    expect(body['payment_terms_days'], 45);
    expect(body['active'], true);
    expect(find.text('Acme Drives'), findsOneWidget);
    expect(find.byKey(const ValueKey('supplier-edit')), findsOneWidget);
  });

  testWidgets('is read-only without the write right', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/suppliers/s1': (_) => _supplier(),
      'GET /api/v1/suppliers/s1/products': (_) => [_price()],
    });
    await _app(tester, http, initial: '/suppliers/s1');
    expect(find.text('MOT-1 · Motor 1kW'), findsOneWidget);
    expect(find.byKey(const ValueKey('supplier-edit')), findsNothing);
    expect(find.byKey(const ValueKey('price-add')), findsNothing);
    expect(find.byKey(const ValueKey('price-edit-p1')), findsNothing);
    expect(find.byKey(const ValueKey('price-remove-p1')), findsNothing);
  });

  testWidgets('adds, updates and removes a price list entry', (tester) async {
    final prices = <Map<String, Object?>>[_price()];
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers/s1': (_) => _supplier(),
      'GET /api/v1/suppliers/s1/products': (_) => prices,
      'GET /api/v1/products': (_) => {
        'total': 1,
        'items': [
          {
            'id': 'p2',
            'code': 'GBX-2',
            'name': 'Gearbox',
            'description': '',
            'active': true,
            'pricing_type': 'fixed',
            'product_type': 'purchased',
            'tracking': 'none',
            'unit': 'pcs',
            'vat_rate': '21',
          },
        ],
      },
      'POST /api/v1/suppliers/s1/products/p2': (b) {
        prices.add(_price(productId: 'p2', code: 'GBX-2', name: 'Gearbox'));
        return prices.last;
      },
      'POST /api/v1/suppliers/s1/products/p1': (b) {
        prices[0] = _price(price: '13.0000');
        return prices[0];
      },
      'DELETE /api/v1/suppliers/s1/products/p1': (_) {
        prices.removeAt(0);
        return null;
      },
    });
    await _app(tester, http, initial: '/suppliers/s1');
    expect(find.text('12,5 EUR'), findsOneWidget);

    // Validation first: nothing chosen.
    await tester.tap(find.byKey(const ValueKey('price-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('price-save')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a product.'), findsOneWidget);

    // The picker's products come from the product search.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('price-product')),
        matching: find.byType(TextField),
      ),
      'gear',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('GBX-2 · Gearbox').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('price-price')), '99,5');
    await tester.enterText(find.byKey(const ValueKey('price-lead')), '7');
    await tester.tap(find.byKey(const ValueKey('price-save')));
    await tester.pumpAndSettle();
    final added = http.bodies['POST /api/v1/suppliers/s1/products/p2']! as Map;
    expect(added['unit_price'], '99.5');
    expect(added['lead_time_days'], 7);
    expect(added['currency'], 'EUR');
    expect(find.text('GBX-2 · Gearbox'), findsOneWidget);

    // Update the existing entry.
    await tester.tap(find.byKey(const ValueKey('price-edit-p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('price-price')), '13');
    await tester.tap(find.byKey(const ValueKey('price-save')));
    await tester.pumpAndSettle();
    expect(
      (http.bodies['POST /api/v1/suppliers/s1/products/p1']!
          as Map)['unit_price'],
      '13',
    );
    expect(find.text('13 EUR'), findsOneWidget);

    // Remove it after confirming.
    await tester.tap(find.byKey(const ValueKey('price-remove-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('price-remove-confirm')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('DELETE /api/v1/suppliers/s1/products/p1'));
    expect(find.text('MOT-1 · Motor 1kW'), findsNothing);
  });

  testWidgets('a failed removal shows a snack bar', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers/s1': (_) => _supplier(),
      'GET /api/v1/suppliers/s1/products': (_) => [_price()],
      'DELETE /api/v1/suppliers/s1/products/p1': (_) => const FakeStatus(403, {
        'error': 'forbidden',
        'message': 'Not allowed',
      }),
    });
    await _app(tester, http, initial: '/suppliers/s1');
    await tester.tap(find.byKey(const ValueKey('price-remove-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('price-remove-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Not allowed'), findsOneWidget);
    expect(find.text('MOT-1 · Motor 1kW'), findsOneWidget);
  });

  testWidgets('a missing supplier shows the error with retry', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read']),
      'GET /api/v1/suppliers/zz': (_) => const FakeStatus(404, {
        'error': 'not_found',
        'message': 'Unknown supplier',
      }),
    });
    await _app(tester, http, initial: '/suppliers/zz');
    expect(find.text('Unknown supplier'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  group('navigation', () {
    Future<void> shell(WidgetTester tester, List<String> perms) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(perms),
        'GET /api/v1/suppliers': (_) => [_supplier()],
        'GET /api/v1/quotations': (_) => {'items': <Object?>[], 'total': 0},
      });
      final router = GoRouter(
        initialLocation: perms.contains('purchasing.read')
            ? '/purchasing'
            : '/orders',
        routes: [
          ShellRoute(
            builder: (c, s, child) =>
                AppShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(
                path: '/purchasing',
                builder: (_, _) => const PurchasingPage(),
              ),
              GoRoute(
                path: '/orders',
                builder: (_, _) => const Text('ORDERS LIST'),
              ),
            ],
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

    testWidgets('Purchasing is shown with the read right', (tester) async {
      await shell(tester, ['purchasing.read', 'orders.read']);
      expect(find.text('Purchasing'), findsOneWidget);
      expect(find.text('Acme Motors'), findsOneWidget);
    });

    testWidgets('Purchasing is hidden without the read right', (tester) async {
      await shell(tester, ['orders.read']);
      expect(find.text('Purchasing'), findsNothing);
      expect(find.text('ORDERS LIST'), findsOneWidget);
    });
  });

  test('a supplier is a detail location with a tab label', () {
    expect(isDetailLocation('/suppliers/abcdef123456'), isTrue);
    expect(isDetailLocation('/suppliers'), isFalse);
    final l = lookupAppLocalizations(const Locale('en'));
    expect(
      tabLabel(l, const WorkTab(id: 1, location: '/suppliers/abcdef123456')),
      'Supplier abcdef12',
    );
    expect(
      tabLabel(
        l,
        const WorkTab(id: 1, location: '/suppliers/s1', title: 'Acme Motors'),
      ),
      'Acme Motors',
    );
  });

  testWidgets('the purchasing page shows a /me error with retry', (
    tester,
  ) async {
    var fail = true;
    final http = FakeHttp({
      'GET /api/v1/me': (_) => fail
          ? const FakeStatus(500, {'error': 'x', 'message': 'Me failed'})
          : meJson(['purchasing.read']),
      'GET /api/v1/suppliers': (_) => [_supplier()],
    });
    await _app(tester, http, initial: '/purchasing');
    expect(find.text('Me failed'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('purchasing-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Acme Motors'), findsOneWidget);
  });

  testWidgets('inputs are disabled while the create request is pending', (
    tester,
  ) async {
    final gate = Completer<void>();
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers': (_) => <Object?>[],
      'POST /api/v1/suppliers': (_) =>
          const FakeStatus(409, {'error': 'c', 'message': 'Code in use'}),
    });
    await _app(tester, http, initial: '/purchasing');
    await tester.tap(find.text('New supplier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('supplier-name')), 'X');
    await tester.tap(find.byKey(const ValueKey('supplier-save')));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('supplier-name')),
    );
    expect(field.enabled, isFalse);
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('supplier-name')))
          .enabled,
      isTrue,
    );
  });

  testWidgets('editing the product text drops the selected product', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['purchasing.read', 'purchasing.write']),
      'GET /api/v1/suppliers/s1': (_) => _supplier(),
      'GET /api/v1/suppliers/s1/products': (_) => <Object?>[],
      'GET /api/v1/products': (_) => {
        'total': 1,
        'items': [
          {
            'id': 'p2',
            'code': 'GBX-2',
            'name': 'Gearbox',
            'description': '',
            'active': true,
            'pricing_type': 'fixed',
            'product_type': 'purchased',
            'tracking': 'none',
            'unit': 'pcs',
            'vat_rate': '21',
          },
        ],
      },
    });
    await _app(tester, http, initial: '/suppliers/s1');
    await tester.tap(find.byKey(const ValueKey('price-add')));
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('price-product')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, 'gear');
    await tester.pumpAndSettle();
    await tester.tap(find.text('GBX-2 · Gearbox').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('price-price')), '5');
    await tester.enterText(input, 'something else');
    await tester.tap(find.byKey(const ValueKey('price-save')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a product.'), findsOneWidget);
    expect(http.requests.where((r) => r.startsWith('POST')), isEmpty);
  });

  test('a supplier detail falls back to the purchasing section', () {
    expect(sectionOfDetail('/suppliers/s1'), '/purchasing');
    expect(sectionOfDetail('/orders/o1'), '/orders');
  });
}
