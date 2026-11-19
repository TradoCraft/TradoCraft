import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shortcuts/host.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/search_picker.dart';

import 'fake_http.dart';

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
  ...pricingFlags('list'),
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
/// product is priced on request, but the price comes from the parent (confirmed with it).
Map<String, Object?> _optionLine() => {
  ..._line('1', '737.20'),
  ...pricingFlags('on_request'),
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

Map<String, Object?> _opportunity(String id, String stage) => {
  'id': id,
  'number': 'OPP-$id',
  'title': 'Deal $id',
  'stage': stage,
  'customer_id': _customerId,
  'customer_name': 'Alpha Installaties NV',
  'expected_value': '1000',
  'probability': 50,
  'notes': '',
  'owner_name': 'Sales',
  'owner_user_id': 'u',
  'created_at': '2026-11-01T10:00:00Z',
  'updated_at': '2026-11-01T10:00:00Z',
};

Map<String, Object?> _otherCustomer(String id) => {
  'id': id,
  'code': 'C-$id',
  'name': 'Customer $id',
  'vat_regime': 'domestic',
  'street': 'Straat 1',
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

Map<String, Object?> _quotation(
  String status, {
  bool configured = false,
  String? opportunityId,
}) => {
  'opportunity_id': opportunityId,
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
  FakeApi(
    this.status, {
    this.configured = false,
    this.linkedOpportunity,
    this.openOpportunities = const [],
  });
  final String status;
  final bool configured;

  /// Opportunity the stored quotation is linked to (may be closed, so not in the open list).
  final String? linkedOpportunity;

  /// Ids returned by the open-opportunities list (answered after a delay, like a slow network).
  final List<String> openOpportunities;
  final requests = <String>[];
  final bodies = <String, Object?>{};

  /// Per customer id: holds the open-opportunities answer until completed (that customer then
  /// has the single opportunity `opp-<id>`).
  final gates = <String, Completer<void>>{};

  /// Holds the answer for customer c1 (quotation q1's customer) until completed; with
  /// [failGatedCustomer] the answer is then a server error.
  Completer<void>? customerGate;
  bool failGatedCustomer = false;
  Completer<void>? saveGate;
  int version = 1;
  bool conflictOnSave = false;

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
        json = {
          ..._quotation(
            status,
            configured: configured,
            opportunityId: linkedOpportunity,
          ),
          'version': version,
        };
      case 'GET /api/v1/customers':
        json = {
          'items': [
            for (final id in ['c2', 'c3']) _otherCustomer(id),
          ],
          'total': 2,
        };
      case 'GET /api/v1/opportunities'
          when gates.containsKey(o.queryParameters['customer_id']):
        final cid = o.queryParameters['customer_id'] as String;
        await gates[cid]!.future;
        json = {
          'items': [
            {..._opportunity('opp-$cid', 'proposal'), 'customer_id': cid},
          ],
          'total': 1,
        };
      case 'GET /api/v1/opportunities':
        await Future<void>.delayed(const Duration(milliseconds: 100));
        json = {
          'items': [
            for (final id in openOpportunities) _opportunity(id, 'proposal'),
          ],
          'total': openOpportunities.length,
        };
      case 'GET /api/v1/opportunities/opp-closed':
        json = _opportunity('opp-closed', 'won');
      case 'GET /api/v1/opportunities/opp1':
        json = _opportunity('opp1', 'proposal');
      case 'GET /api/v1/quotations/q2':
        json = {
          ..._quotation(status),
          'id': 'q2',
          'number': 'Q-B',
          'notes': 'Notes B',
          'customer_id': 'c2',
        };
      case 'GET /api/v1/customers/c2':
        json = _otherCustomer('c2');
      case 'PUT /api/v1/quotations/q2':
        json = {..._quotation(status), 'id': 'q2', 'number': 'Q-B'};
      case 'GET /api/v1/customers/$_customerId':
        if (customerGate != null) {
          await customerGate!.future;
          if (failGatedCustomer) {
            return ResponseBody.fromString(
              '{"error":"internal","message":"boom"}',
              500,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
        }
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
          ...pricingFlags('list'),
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
          ...pricingFlags('on_request'),
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
        if (saveGate != null) await saveGate!.future;
        if (conflictOnSave) {
          return ResponseBody.fromString(
            '{"code":"record_changed","message":"changed"}',
            409,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
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
  bool keys = false,
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
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
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: keys ? (c, child) => ShortcutsHost(child: child!) : null,
        home: QuotationScreen(id: _quotationId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<FakeApi> _pumpNew(
  WidgetTester tester, {
  required String opportunityId,
  List<String> open = const [],
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeApi('draft', openOpportunities: open);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuotationScreen(
          customerId: _customerId,
          opportunityId: opportunityId,
        ),
      ),
    ),
  );
  // Small steps so frames are built while the opportunity list is still loading.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
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
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<FakeApi> _pumpLinkedDraft(
  WidgetTester tester,
  List<String> gated,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeApi('draft', linkedOpportunity: 'opp-closed');
  for (final id in gated) {
    fake.gates[id] = Completer<void>();
  }
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuotationScreen(id: _quotationId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _changeCustomer(WidgetTester tester, String id) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(SearchPicker<Customer>),
      matching: find.byType(TextField),
    ),
    'c',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Customer $id').last);
  await tester.pump();
}

/// Opens q1 with its customer answer held back, then switches the same screen to q2.
Future<FakeApi> _pumpSwitched(WidgetTester tester, {bool fail = false}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeApi('draft')
    ..customerGate = Completer<void>()
    ..failGatedCustomer = fail;
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = fake;
  Widget app(String id) => ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: QuotationScreen(id: id),
    ),
  );
  await tester.pumpWidget(app(_quotationId));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpWidget(app('q2'));
  await tester.pumpAndSettle();
  fake.customerGate!.complete();
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('failed reload preserves the save baseline and permits retry', (
    tester,
  ) async {
    final fake = await _pumpLinkedDraft(tester, []);
    fake.conflictOnSave = true;
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(find.text('Reload'), findsOneWidget);
    fake.version = 2;
    fake.customerGate = Completer<void>();
    fake.failGatedCustomer = true;
    await tester.tap(find.text('Reload'));
    await tester.pump();
    fake.customerGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Reload'), findsOneWidget);
    fake.conflictOnSave = false;
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    final body = fake.bodies['PUT /api/v1/quotations/$_quotationId'] as Map;
    expect(body['expected_version'], 1);
    expect(find.text('Reload'), findsNothing);
  });

  testWidgets('a save finishing after disposal does not restart the watcher', (
    tester,
  ) async {
    final fake = await _pumpLinkedDraft(tester, []);
    fake.saveGate = Completer<void>();
    await tester.tap(find.text('Save draft'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    final subscriptions = fake.requests
        .where((r) => r.contains('/events/records'))
        .length;
    fake.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      fake.requests.where((r) => r.contains('/events/records')).length,
      subscriptions,
    );
  });

  testWidgets(
    'dropping a linked opportunity refreshes a saved blank-year draft',
    (tester) async {
      final fake = await _pumpLinkedDraft(tester, ['c2']);
      await _changeCustomer(tester, 'c2');
      fake.gates['c2']!.complete();
      await tester.pumpAndSettle();
      final body = fake.bodies['POST /api/v1/pricing/preview'] as Map;
      expect(body['opportunity_id'], isNull);
      expect(body['clear_building_construction_year'], isTrue);
    },
  );

  testWidgets('VAT and building year controls are disabled during save', (
    tester,
  ) async {
    final fake = await _pumpLinkedDraft(tester, []);
    fake.saveGate = Completer<void>();
    await tester.tap(find.text('Save draft'));
    await tester.pump();
    final year = tester.widget<TextField>(
      find.byKey(const ValueKey('buildingConstructionYear')),
    );
    expect(year.enabled, isFalse);
    final vat = tester.widget<DropdownButtonFormField<String?>>(
      find.descendant(
        of: find.byKey(const ValueKey('vat-regime-override')),
        matching: find.byType(DropdownButtonFormField<String?>),
      ),
    );
    expect(vat.onChanged, isNull);
    fake.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('buildingConstructionYear')),
          )
          .enabled,
      isTrue,
    );
  });

  testWidgets(
    'a slow load of the previous quotation does not overwrite the new one',
    (tester) async {
      final fake = await _pumpSwitched(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Q-B'), findsWidgets);
      expect(find.textContaining('Q2026-00001'), findsNothing);
      expect(find.text('Notes B'), findsOneWidget);
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(fake.bodies.containsKey('PUT /api/v1/quotations/q2'), isTrue);
      expect(
        fake.bodies.containsKey('PUT /api/v1/quotations/$_quotationId'),
        isFalse,
      );
    },
  );

  testWidgets('an error from the stale load shows no error banner', (
    tester,
  ) async {
    await _pumpSwitched(tester, fail: true);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.text('Notes B'), findsOneWidget);
  });

  testWidgets(
    'changing the customer hides the old customer opportunities while loading',
    (tester) async {
      await _pumpLinkedDraft(tester, ['c2']);
      expect(find.textContaining('OPP-opp-closed'), findsOneWidget);
      await _changeCustomer(tester, 'c2');
      await tester.pump(const Duration(milliseconds: 10));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('OPP-opp-closed'), findsNothing);
    },
  );

  testWidgets('a late answer for a previous customer is ignored', (
    tester,
  ) async {
    final fake = await _pumpLinkedDraft(tester, ['c2', 'c3']);
    await _changeCustomer(tester, 'c2');
    await _changeCustomer(tester, 'c3');
    fake.gates['c3']!.complete();
    await tester.pumpAndSettle();
    fake.gates['c2']!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('opp-'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('OPP-opp-c3'), findsWidgets);
    expect(find.textContaining('OPP-opp-c2'), findsNothing);
  });

  testWidgets(
    'new quotation with a preselected opportunity builds while the list loads',
    (tester) async {
      await _pumpNew(tester, opportunityId: 'opp1', open: ['opp1']);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('OPP-opp1'), findsOneWidget);
    },
  );

  testWidgets(
    'a preselected opportunity missing from the open list is fetched and kept',
    (tester) async {
      final fake = await _pumpNew(tester, opportunityId: 'opp-closed');
      expect(tester.takeException(), isNull);
      expect(fake.requests, contains('GET /api/v1/opportunities/opp-closed'));
      expect(find.textContaining('OPP-opp-closed'), findsOneWidget);
    },
  );

  testWidgets('a draft linked to a closed opportunity keeps the link on save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeApi('draft', linkedOpportunity: 'opp-closed');
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = fake;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: QuotationScreen(id: _quotationId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('OPP-opp-closed'), findsOneWidget);
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    final body = fake.bodies['PUT /api/v1/quotations/$_quotationId'] as Map;
    expect(body['opportunity_id'], 'opp-closed');
  });

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

  testWidgets('line calculations preview, commit on blur and save once', (
    tester,
  ) async {
    final fake = await _pump(tester, 'draft');
    final quantity = find.widgetWithText(TextField, '1');
    final discount = find.widgetWithText(TextField, '0');
    const preview = 'POST /api/v1/pricing/preview';

    await tester.enterText(quantity, '+= (2 * 3)');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect((fake.bodies[preview] as Map)['lines'][0]['quantity'], '7');

    await tester.enterText(discount, '10%');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '7'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '7'), '*=2');
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    final saved = fake.bodies['PUT /api/v1/quotations/$_quotationId'] as Map;
    expect(saved['lines'][0]['quantity'], '14');
    expect(saved['lines'][0]['line_discount_percent'], '10');
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

  group('keyboard', () {
    String? focusedText() {
      final f = FocusManager.instance.primaryFocus;
      return f?.context?.findAncestorWidgetOfExactType<EditableText>() == null
          ? null
          : f!.context!.findAncestorWidgetOfExactType<EditableText>()!
                .controller
                .text;
    }

    testWidgets('Alt+L puts the cursor in the add-product picker', (
      tester,
    ) async {
      await _pump(tester, 'draft', keys: true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      final picker = find.descendant(
        of: find.byType(SearchPicker<Product>),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(picker).focusNode.hasFocus, isTrue);
    });

    testWidgets(
      'Alt+L scrolls to the add-product picker when it is not built yet',
      (tester) async {
        // A short window: the page is a lazy list, the picker is far below what is built.
        await _pump(tester, 'draft', keys: true, size: const Size(1400, 240));
        expect(find.byType(SearchPicker<Product>), findsNothing);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        final picker = find.descendant(
          of: find.byType(SearchPicker<Product>),
          matching: find.byType(EditableText),
        );
        expect(picker, findsOneWidget);
        expect(tester.widget<EditableText>(picker).focusNode.hasFocus, isTrue);
      },
    );

    testWidgets('a sent quotation has no add-line shortcut', (tester) async {
      await _pump(tester, 'sent', keys: true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(handled, isFalse);
    });

    testWidgets('Ctrl+Right and Ctrl+Left jump along a line', (tester) async {
      await _pump(tester, 'draft', keys: true);
      final qty = find.bySemanticsLabel('Quantity');
      await tester.tap(
        find.descendant(of: qty, matching: find.byType(TextField)),
      );
      await tester.pump();
      expect(focusedText(), '1');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      // The last field of the line is its discount.
      expect(focusedText(), '0');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(focusedText(), '1');
    });
  });
}
