import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/products/packaging_dialog.dart';
import 'package:tradocraft_app/features/products/product_form.dart';
import 'package:tradocraft_app/features/products/product_screen.dart';
import 'package:tradocraft_app/features/shipping/shipping_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _category(
  String id,
  String code, {
  bool requires = false,
  bool active = true,
}) => {
  'id': id,
  'code': code,
  'name': 'Name $code',
  'description': 'About $code',
  'requires_shipping_quote': requires,
  'active': active,
  'product_count': 2,
};

Map<String, Object?> _product({
  String? category,
  int? length,
  int? width,
  int? height,
  int? weight,
}) => {
  'id': 'p1',
  'code': 'PANEL-1',
  'name': 'Large panel',
  'description': '',
  'unit': 'pcs',
  'product_type': 'purchased',
  'tracking': 'none',
  'pricing_type': 'list',
  'vat_rate': '21',
  'active': true,
  'packaging_category_id': category,
  'packaging_category_code': category == null ? null : 'FLAT',
  'length_mm': length,
  'width_mm': width,
  'height_mm': height,
  'weight_g': weight,
};

Map<String, Object?> _request(
  String id,
  String status, {
  String? carrier,
  String? amount,
}) => {
  'id': id,
  'quotation_id': 'q-$id',
  'quotation_number': 'Q2026-0000$id',
  'quotation_revision': 1,
  'customer_name': 'Customer $id',
  'delivery_country_code': 'NL',
  'status': status,
  'notes': '',
  'carrier': carrier,
  'currency': 'EUR',
  'quoted_amount': amount,
  'requested_at': status == 'open' ? null : '2026-11-06T10:00:00Z',
  'created_at': '2026-11-05T10:00:00Z',
};

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http,
  Widget home, {
  List<RouteBase> routes = const [],
}) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      ...routes,
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

/// Opens [dialog] from a button, like the app does, so menus and nested dialogs have an overlay.
Widget _host(Widget dialog) => Builder(
  builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () =>
          showDialog<void>(context: context, builder: (_) => dialog),
      child: const Text('open'),
    ),
  ),
);

Future<void> _pumpDialog(
  WidgetTester tester,
  FakeHttp http,
  Widget dialog,
) async {
  await _pump(tester, http, _host(dialog));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('product form', () {
    FakeHttp http({Object? Function(Object?)? save}) => FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.write']),
      'GET /api/v1/families': (_) => [],
      'GET /api/v1/packaging-categories': (_) => [
        _category('k1', 'FLAT', requires: true),
        _category('k2', 'OLD', active: false),
        _category('k3', 'BOX'),
      ],
      'PUT /api/v1/products/p1': save ?? (_) => _product(),
    });

    Product existing() => Product.fromJson(_product());

    testWidgets('sends packaging category and dimensions', (tester) async {
      final h = http();
      await _pumpDialog(tester, h, ProductForm(product: existing()));
      final dropdown = find.widgetWithText(
        DropdownButtonFormField<String?>,
        'Packaging category',
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      // Inactive categories are not offered.
      expect(find.text('OLD · Name OLD'), findsNothing);
      await tester.tap(find.text('FLAT · Name FLAT').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Length (mm)'),
        '2400',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Width (mm)'),
        '1200',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Height (mm)'),
        '40',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Weight (g)'),
        '35000',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['PUT /api/v1/products/p1'] as Map;
      expect(body['packaging_category_id'], 'k1');
      expect(body['length_mm'], 2400);
      expect(body['width_mm'], 1200);
      expect(body['height_mm'], 40);
      expect(body['weight_g'], 35000);
    });

    testWidgets('empty dimensions are omitted', (tester) async {
      final h = http();
      await _pumpDialog(tester, h, ProductForm(product: existing()));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['PUT /api/v1/products/p1'] as Map;
      expect(body.containsKey('length_mm'), isFalse);
      expect(body.containsKey('packaging_category_id'), isFalse);
    });

    for (final bad in ['0', '-5', '12.5', 'abc']) {
      testWidgets('rejects "$bad" client-side', (tester) async {
        final h = http();
        await _pumpDialog(tester, h, ProductForm(product: existing()));
        await tester.enterText(
          find.widgetWithText(TextField, 'Weight (g)'),
          bad,
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.textContaining('positive whole numbers'), findsOneWidget);
        expect(h.requests, isNot(contains('PUT /api/v1/products/p1')));
      });
    }
  });

  testWidgets('the product header shows packaging category and dimensions', (
    tester,
  ) async {
    final h = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.read']),
      'GET /api/v1/products/p1': (_) => _product(
        category: 'k1',
        length: 2400,
        width: 1200,
        height: 40,
        weight: 35000,
      ),
      'GET /api/v1/products/p1/prices': (_) => [],
    });
    await _pump(tester, h, const ProductScreen(id: 'p1'));
    expect(find.text('FLAT'), findsOneWidget);
    expect(find.text('2400 x 1200 x 40 mm'), findsOneWidget);
    expect(find.text('35000 g'), findsOneWidget);
  });

  group('packaging dialog', () {
    FakeHttp http() => FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.write']),
      'GET /api/v1/packaging-categories': (_) => [
        _category('k1', 'FLAT', requires: true),
      ],
      'POST /api/v1/packaging-categories': (_) => _category('k9', 'CRATE'),
      'PUT /api/v1/packaging-categories/k1': (_) => _category('k1', 'FLAT'),
    });

    testWidgets('creates a category', (tester) async {
      final h = http();
      await _pumpDialog(tester, h, const PackagingDialog());
      expect(find.text('FLAT · Name FLAT'), findsOneWidget);
      expect(find.textContaining('Requires a shipping quote'), findsOneWidget);
      await tester.tap(find.text('New packaging category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Code'), 'CRATE');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Crate');
      await tester.tap(find.text('Requires a shipping quote'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/packaging-categories'] as Map;
      expect(body['code'], 'CRATE');
      expect(body['name'], 'Crate');
      expect(body['requires_shipping_quote'], true);
      expect(body['active'], true);
    });

    testWidgets('edits a category', (tester) async {
      final h = http();
      await _pumpDialog(tester, h, const PackagingDialog());
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Requires a shipping quote').last);
      await tester.pump();
      await tester.tap(find.text('Active'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['PUT /api/v1/packaging-categories/k1'] as Map;
      expect(body['code'], 'FLAT');
      expect(body['requires_shipping_quote'], false);
      expect(body['active'], false);
    });

    testWidgets('read-only without products.write', (tester) async {
      final h = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.read']),
        'GET /api/v1/packaging-categories': (_) => [_category('k1', 'FLAT')],
      });
      await _pumpDialog(tester, h, const PackagingDialog());
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('New packaging category'), findsNothing);
    });
  });

  group('shipping page', () {
    FakeHttp http({Map<String, Object? Function(Object?)> extra = const {}}) =>
        FakeHttp({
          'GET /api/v1/me': (_) => meJson(['shipping.manage']),
          'GET /api/v1/shipping-requests': (_) => [
            _request('1', 'open'),
            _request('2', 'requested', carrier: 'Transco'),
          ],
          ...extra,
        });

    final quotePage = GoRoute(
      path: '/quotations/:id',
      builder: (_, s) => Text('quotation ${s.pathParameters['id']}'),
    );

    testWidgets('lists the work queue with actions per status', (tester) async {
      final h = http();
      await _pump(tester, h, const ShippingPage());
      expect(find.textContaining('Q2026-00001'), findsOneWidget);
      expect(find.text('Customer 2'), findsOneWidget);
      expect(find.text('Transco'), findsOneWidget);
      // Only the open one can be marked as requested; both can be quoted.
      expect(find.text('Mark as requested'), findsOneWidget);
      expect(find.text('Enter quote'), findsNWidgets(2));
      expect(h.queries.last['status'], isNull);
    });

    testWidgets('the status filter asks the server for that status', (
      tester,
    ) async {
      final h = http(
        extra: {
          'GET /api/v1/shipping-requests': (_) => [
            _request('3', 'quoted', carrier: 'Transco', amount: '250.00'),
          ],
        },
      );
      await _pump(tester, h, const ShippingPage());
      await tester.tap(find.text('Open and requested'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('quoted').last);
      await tester.pumpAndSettle();
      expect(h.queries.last['status'], 'quoted');
      expect(find.text('€ 250,00'), findsOneWidget);
      expect(find.text('Enter quote'), findsNothing);
    });

    testWidgets('mark as requested posts carrier and notes', (tester) async {
      final h = http(
        extra: {
          'POST /api/v1/shipping-requests/1/request': (_) =>
              _request('1', 'requested', carrier: 'Transco'),
        },
      );
      await _pump(tester, h, const ShippingPage());
      await tester.tap(find.text('Mark as requested'));
      await tester.pumpAndSettle();
      // A carrier is required.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the carrier.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Carrier'),
        'Transco, DHL',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'Crated');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/shipping-requests/1/request'] as Map;
      expect(body, {'carrier': 'Transco, DHL', 'notes': 'Crated'});
      // The list reloads after the action.
      expect(
        h.requests.where((r) => r == 'GET /api/v1/shipping-requests'),
        hasLength(2),
      );
    });

    testWidgets('enter quote posts the amount in the quotation currency', (
      tester,
    ) async {
      final h = http(
        extra: {
          'POST /api/v1/shipping-requests/2/quote': (_) =>
              _request('2', 'quoted', carrier: 'Transco', amount: '250.50'),
        },
      );
      await _pump(tester, h, const ShippingPage());
      await tester.tap(find.text('Enter quote').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid amount.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount'),
        '250,50',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = h.bodies['POST /api/v1/shipping-requests/2/quote'] as Map;
      expect(body['amount'], '250.5');
      expect(body['currency'], 'EUR');
      expect(body['carrier'], 'Transco');
    });

    testWidgets('a refused quote shows the server message', (tester) async {
      final h = http(
        extra: {
          'POST /api/v1/shipping-requests/2/quote': (_) => FakeStatus(409, {
            'error': 'conflict',
            'message': 'The quotation is no longer a draft',
          }),
        },
      );
      await _pump(tester, h, const ShippingPage());
      await tester.tap(find.text('Enter quote').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '10');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('The quotation is no longer a draft'), findsOneWidget);
    });

    testWidgets('tapping a row opens the quotation', (tester) async {
      await _pump(tester, http(), const ShippingPage(), routes: [quotePage]);
      await tester.tap(find.text('Customer 1'));
      await tester.pumpAndSettle();
      expect(find.text('quotation q-1'), findsOneWidget);
    });
  });

  group('navigation', () {
    Future<void> shell(WidgetTester tester, List<String> perms) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(perms),
        'GET /api/v1/shipping-requests': (_) => [],
      });
      final router = GoRouter(
        initialLocation: '/shipping',
        routes: [
          ShellRoute(
            builder: (c, s, child) =>
                AppShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(path: '/shipping', builder: (_, _) => const Text('SHIP')),
              GoRoute(path: '/orders', builder: (_, _) => const Text('ORDERS')),
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

    testWidgets('Shipping requests needs shipping.manage', (tester) async {
      await shell(tester, ['shipping.manage', 'orders.read']);
      expect(find.text('Shipping requests'), findsOneWidget);
      expect(find.text('SHIP'), findsOneWidget);
    });

    testWidgets('without shipping.manage the destination is hidden', (
      tester,
    ) async {
      await shell(tester, ['orders.read']);
      expect(find.text('Shipping requests'), findsNothing);
      expect(find.text('ORDERS'), findsOneWidget);
    });
  });
}
