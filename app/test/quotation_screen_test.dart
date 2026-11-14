import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

const _quotationId = 'q1';
const _customerId = 'c1';
const _productId = 'p1';

Map<String, Object?> _line(String qty, String total) => {
  'position': 1,
  'product_id': _productId,
  'product_code': 'UNIT-100',
  'description': 'Process unit 100',
  'unit': 'pcs',
  'quantity': qty,
  'list_unit_price': '3880.0000',
  'line_discount_percent': '0',
  'pricing_type': 'list',
  'rebate_percent': '5',
  'rebate_source': 'general',
  'price_confirmed': true,
  'net_unit_price': '3686.0000',
  'line_total': total,
  'vat_rate': '21',
  'production_remark': 'Weld first',
  'customer_remark': 'Delivered on a pallet',
};

/// A configured quotation's option line: priced at 20 % of line 1, in its own section. Its
/// product is indicative, but the price comes from the parent (confirmed with it).
Map<String, Object?> _optionLine() => {
  ..._line('1', '737.20'),
  'pricing_type': 'indicative',
  'position': 2,
  'product_id': 'p2',
  'product_code': 'COAT-PROT',
  'description': 'Corrosion protection',
  'section': 'Hall 1',
  'comment': 'segments 1-2',
  'parent_position': 1,
  'percent_of_parent': '20',
  'percent_base': 'parent_list_unit_price',
};

Map<String, Object?> _quotation(String status, {bool configured = false}) => {
  'id': _quotationId,
  'company_id': 'co',
  'number': 'Q2026-00001',
  'revision': 1,
  'status': status,
  'customer_id': _customerId,
  'customer_name': 'Alpha Installaties NV',
  'customer_vat_number': null,
  'vat_regime': 'domestic',
  'customer_street': 'Havenlaan 10',
  'customer_postal_code': '2000',
  'customer_city': 'Antwerpen',
  'customer_country_code': 'BE',
  'customer_language': 'nl',
  'price_zone_code': 'Z2',
  'customer_discount_percent': '5',
  'currency': 'EUR',
  'quote_date': '2026-11-05',
  'purpose': 'installation',
  'shipping_status': 'not_required',
  'price_date': '2026-11-05',
  'valid_until': '2026-12-05',
  'notes': '',
  'subtotal': '3686.00',
  'vat_total': '774.06',
  'total': '4460.06',
  'supersedes_id': null,
  'created_by': 'u',
  'created_at': '2026-11-05T10:00:00Z',
  'updated_at': '2026-11-05T10:00:00Z',
  'sent_at': null,
  'lines': [_line('1', '3686.00'), if (configured) _optionLine()],
  'warnings': <Object?>[],
  'suggestions': <Object?>[],
  'vat_groups': [
    {'vat_rate': '21', 'base': '3686.00', 'vat': '774.06'},
  ],
};

/// Fake backend: records requests and answers like the Rust API would.
class FakeApi implements HttpClientAdapter {
  FakeApi(this.status, {this.configured = false});
  final String status;
  final bool configured;
  final requests = <String>[];
  final bodies = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final key = '${o.method} ${o.path}';
    requests.add(key);
    bodies[key] = o.data == null ? null : jsonDecode(jsonEncode(o.data));
    Object? json;
    switch (key) {
      case 'GET /api/v1/quotations/$_quotationId':
        json = _quotation(status, configured: configured);
      case 'GET /api/v1/customers/$_customerId':
        json = {
          'id': _customerId,
          'code': 'C0001',
          'name': 'Alpha Installaties NV',
          'vat_regime': 'domestic',
          'street': 'Havenlaan 10',
          'postal_code': '2000',
          'city': 'Antwerpen',
          'country_code': 'BE',
          'language': 'nl',
          'active': true,
          'price_zone_id': 'z2',
          'price_zone_code': 'Z2',
          'discount_percent': '5',
          'payment_terms_days': 30,
        };
      case 'GET /api/v1/products/$_productId':
        json = {
          'id': _productId,
          'code': 'UNIT-100',
          'name': 'Process unit 100',
          'description': '',
          'unit': 'pcs',
          'product_type': 'manufactured',
          'tracking': 'serial',
          'pricing_type': 'list',
          'vat_rate': '21',
          'active': true,
          'default_production_remark': 'Weld first',
        };
      case 'GET /api/v1/products/$_productId/remark-history':
        // One distinct text per scope, so the tests can tell the tabs apart.
        final scope = o.queryParameters['scope'];
        json = [
          {
            'text': 'Remark of scope $scope',
            'last_used': '2026-10-01',
            'use_count': 3,
            'last_quotation_number': 'Q2026-00009',
          },
        ];
      case 'GET /api/v1/products/p2':
        json = {
          'id': 'p2',
          'code': 'COAT-PROT',
          'name': 'Corrosion protection',
          'description': '',
          'unit': 'pcs',
          'product_type': 'service',
          'tracking': 'none',
          'pricing_type': 'indicative',
          'vat_rate': '21',
          'active': true,
        };
      case 'POST /api/v1/pricing/preview':
        // The server is the only place that calculates: 2 units -> 7372.00.
        json = {
          'price_zone_code': 'Z2',
          'customer_discount_percent': '5',
          'quote_date': '2026-11-05',
          'price_date': '2026-11-05',
          'unconfirmed_lines': 0,
          'warnings': <Object?>[],
          'suggestions': <Object?>[],
          'lines': [_line('2', '7372.00')],
          'vat_groups': [
            {'vat_rate': '21', 'base': '7372.00', 'vat': '1548.12'},
          ],
          'subtotal': '7372.00',
          'vat_total': '1548.12',
          'total': '8920.12',
        };
      case 'PUT /api/v1/quotations/$_quotationId':
        json = _quotation(status, configured: configured);
      case 'POST /api/v1/quotations/$_quotationId/convert':
        json = {
          'created_at': '2026-11-06T09:00:00Z',
          'lines': <Object?>[],
          'notes': '',
          'cancel_reason': '',
          'confirmation_note': '',
          'revision': 1,
          'revision_status': 'draft',
          'revisions': <Object?>[],
          'warnings': <Object?>[],
          'suggestions': <Object?>[],
          'vat_total': '774.06',
          'order': {
            'id': 'o1',
            'number': 'O2026-00001',
            'status': 'draft',
            'current_revision': 1,
            'priority': 'normal',
            'quotation_id': _quotationId,
            'quotation_number': 'Q2026-00001',
            'quotation_revision': 1,
            'customer_id': _customerId,
            'customer_name': 'Alpha Installaties NV',
            'customer_reference': 'PO-77',
            'order_date': '2026-11-06',
            'purpose': 'installation',
            'salesperson_id': 'u',
            'salesperson_name': 'Sales',
            'currency': 'EUR',
            'subtotal': '3686.00',
            'total': '4460.06',
          },
        };
      case 'GET /api/v1/me':
        json = {
          'user_id': 'u',
          'email': 'sales@example.com',
          'display_name': 'Sales',
          'roles': ['sales'],
          'permissions': ['quotations.read', 'quotations.write'],
          'modules': [],
          'memberships': [],
          'company': {
            'id': 'co',
            'name': 'Demo',
            'street': '',
            'postal_code': '',
            'city': '',
            'country_code': 'BE',
            'currency': 'EUR',
            'default_language': 'nl',
            'is_primary': true,
          },
        };
      default:
        return ResponseBody.fromString(
          '{"error":"not_found","message":"$key"}',
          404,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
    }
    return ResponseBody.fromString(
      jsonEncode(json),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<FakeApi> _pump(
  WidgetTester tester,
  String status, {
  bool configured = false,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeApi(status, configured: configured);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuotationScreen(id: _quotationId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

/// Like [_pump], inside a router so the screen can navigate to the new order.
Future<FakeApi> _pumpRouted(WidgetTester tester, String status) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeApi(status);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = fake;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => QuotationScreen(id: _quotationId),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) => Text('order page ${state.pathParameters['id']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('draft totals come from the server pricing preview', (
    tester,
  ) async {
    final fake = await _pump(tester, 'draft');
    expect(find.text('Save draft'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '1'), '2');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final body = fake.bodies['POST /api/v1/pricing/preview'] as Map;
    expect((body['lines'] as List).first['quantity'], '2');
    expect(find.text('€ 8.920,12'), findsOneWidget);
    expect(find.text('€ 7.372,00'), findsWidgets);
  });

  testWidgets('the number inputs of a line have accessible names', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, 'draft');
    // The column headers are the only visible labels, so each input carries its header as its name.
    final quantity = tester.getSemantics(find.widgetWithText(TextField, '1'));
    expect(quantity.label, contains('Quantity'));
    expect(quantity.flagsCollection.isTextField, isTrue);
    expect(
      tester.getSemantics(find.widgetWithText(TextField, '0')).label,
      contains('Extra disc.'),
    );
    handle.dispose();
  });

  testWidgets('remarks are loaded, edited and saved with the draft', (
    tester,
  ) async {
    final fake = await _pump(tester, 'draft');
    expect(find.text('Production remark'), findsOneWidget);
    expect(find.text('Customer remark'), findsOneWidget);
    final production = find.byKey(
      const ValueKey('production-remark-$_productId'),
    );
    final customer = find.byKey(const ValueKey('customer-remark-$_productId'));
    expect(
      find.descendant(of: production, matching: find.text('Weld first')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: customer,
        matching: find.text('Delivered on a pallet'),
      ),
      findsOneWidget,
    );

    await tester.enterText(customer, ' Call before delivery ');
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    final body = fake.bodies['PUT /api/v1/quotations/$_quotationId'] as Map;
    final line = (body['lines'] as List).first as Map;
    expect(line['customer_remark'], 'Call before delivery');
    expect(line['production_remark'], 'Weld first');
  });

  testWidgets('the remark history has three scopes and fills the field', (
    tester,
  ) async {
    final fake = await _pump(tester, 'draft');
    await tester.tap(
      find.byKey(const ValueKey('customer-remark-history-$_productId')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('remark-history')), findsOneWidget);
    expect(find.text('This customer'), findsOneWidget);
    expect(find.text('This language'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Remark of scope customer'), findsOneWidget);
    expect(
      find.textContaining('Used 3 times, last on Q2026-00009'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('remark-tab-language')));
    await tester.pumpAndSettle();
    expect(find.text('Remark of scope language'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remark-tab-all')));
    await tester.pumpAndSettle();
    expect(find.text('Remark of scope all'), findsOneWidget);

    // Each scope asked the server with its own filter.
    expect(fake.requests.where((r) => r.contains('remark-history')).length, 3);
    await tester.tap(find.text('Remark of scope all'));
    await tester.pumpAndSettle();
    final customer = find.byKey(const ValueKey('customer-remark-$_productId'));
    expect(
      find.descendant(of: customer, matching: find.text('Remark of scope all')),
      findsOneWidget,
    );
  });

  testWidgets('sent quotation shows the remarks read-only', (tester) async {
    await _pump(tester, 'sent');
    expect(find.textContaining('Delivered on a pallet'), findsOneWidget);
    expect(
      find.textContaining('Production remark: Weld first'),
      findsOneWidget,
    );
  });

  testWidgets('configured draft keeps its structure in preview and save', (
    tester,
  ) async {
    final fake = await _pump(tester, 'draft', configured: true);
    final lines =
        (fake.bodies['POST /api/v1/pricing/preview'] as Map)['lines'] as List;
    expect(lines, hasLength(2));
    expect(lines[0]['parent_position'], isNull);
    expect(lines[1]['parent_position'], 1);
    expect(lines[1]['percent_of_parent'], '20');
    expect(lines[1]['percent_base'], 'parent_list_unit_price');
    expect(lines[1]['section'], 'Hall 1');
    expect(lines[1]['comment'], 'segments 1-2');
    // A percentage line never sends a unit price (it would be refused), nor shows a price field.
    expect(lines[1]['unit_price'], isNull);
    // Section and comment tell repeated products apart.
    expect(find.text('Hall 1 · segments 1-2'), findsOneWidget);

    // Saving sends the same structure.
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    final saved =
        (fake.bodies['PUT /api/v1/quotations/$_quotationId'] as Map)['lines']
            as List;
    expect(saved, hasLength(2));
    expect(saved[1]['parent_position'], 1);
    expect(saved[1]['percent_of_parent'], '20');
    expect(saved[1]['percent_base'], 'parent_list_unit_price');
    expect(saved[1]['section'], 'Hall 1');
    expect(saved[1]['comment'], 'segments 1-2');
    expect(saved[1]['unit_price'], isNull);

    // Removing the parent removes its option too: no dangling percent-of-parent line.
    await tester.tap(find.byTooltip('Remove line').first);
    await tester.pumpAndSettle();
    expect(find.text('COAT-PROT'), findsNothing);
  });

  testWidgets('sent quotation is read-only with follow-up actions', (
    tester,
  ) async {
    final fake = await _pump(tester, 'sent');
    expect(find.text('Save draft'), findsNothing);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('New revision'), findsOneWidget);
    expect(find.text('€ 4.460,06'), findsOneWidget);
    expect(fake.requests, isNot(contains('POST /api/v1/pricing/preview')));
  });

  for (final status in ['sent', 'accepted']) {
    testWidgets('$status quotation offers Convert to order', (tester) async {
      await _pump(tester, status);
      expect(find.text('Convert to order'), findsOneWidget);
    });
  }

  for (final status in ['draft', 'rejected']) {
    testWidgets('$status quotation cannot be converted', (tester) async {
      await _pump(tester, status);
      expect(find.text('Convert to order'), findsNothing);
    });
  }

  testWidgets('Convert to order sends the reference and opens the order', (
    tester,
  ) async {
    final fake = await _pumpRouted(tester, 'sent');
    await tester.tap(find.text('Convert to order'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, ' PO-77 ');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    const key = 'POST /api/v1/quotations/$_quotationId/convert';
    expect(fake.requests, contains(key));
    expect((fake.bodies[key] as Map)['customer_reference'], 'PO-77');
    expect(find.text('order page o1'), findsOneWidget);
  });

  testWidgets('cancelling the reference dialog creates no order', (
    tester,
  ) async {
    final fake = await _pumpRouted(tester, 'accepted');
    await tester.tap(find.text('Convert to order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      fake.requests,
      isNot(contains('POST /api/v1/quotations/$_quotationId/convert')),
    );
    expect(find.text('order page o1'), findsNothing);
  });
}
