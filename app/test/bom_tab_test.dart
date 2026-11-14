import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/products/bom_tab.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

const _product = Product(
  id: 'p-unit',
  code: 'UNIT-100',
  name: 'Process unit 100',
  description: '',
  unit: 'pcs',
  productType: 'manufactured',
  vatRate: '21',
  tracking: 'serial',
  pricingType: 'list',
  active: true,
);

Map<String, Object?> _line(
  int pos,
  String code,
  String name,
  String qty, {
  bool sub = false,
  String unit = 'pcs',
}) => {
  'position': pos,
  'component_product_id': 'p-$code',
  'component_code': code,
  'component_name': name,
  'component_unit': unit,
  'component_type': sub ? 'manufactured' : 'purchased',
  'component_tracking': 'none',
  'component_has_bom': sub,
  'quantity': qty,
  'scrap_percent': '0',
  'notes': '',
};

Map<String, Object?> _node(
  int? parent,
  int level,
  String code,
  String unit,
  String qty,
  bool leaf,
) => {
  'parent_index': parent,
  'level': level,
  'product_id': 'p-$code',
  'code': code,
  'name': code,
  'unit': unit,
  'product_type': leaf ? 'purchased' : 'manufactured',
  'quantity_per_parent': '1',
  'scrap_percent': '0',
  'required_quantity': qty,
  'is_leaf': leaf,
};

class _FakeApi implements HttpClientAdapter {
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final key = '${o.method} ${o.path}';
    requests.add('$key ${o.queryParameters}');
    final Object? json = switch (key) {
      'GET /api/v1/products/p-unit/boms' => [
        {
          'id': 'b1',
          'product_id': 'p-unit',
          'revision': 1,
          'status': 'active',
          'line_count': 2,
          'notes': '',
          'created_at': '2026-11-01T10:00:00Z',
          'activated_at': '2026-11-01T10:00:00Z',
        },
      ],
      'GET /api/v1/boms/b1' => {
        'id': 'b1',
        'product_id': 'p-unit',
        'product_code': 'UNIT-100',
        'product_name': 'Process unit 100',
        'revision': 1,
        'status': 'active',
        'notes': '',
        'created_at': '2026-11-01T10:00:00Z',
        'activated_at': '2026-11-01T10:00:00Z',
        'lines': [
          _line(1, 'FRAME-A', 'Frame assembly', '1', sub: true),
          _line(2, 'PUMP-05', 'Pump', '2'),
        ],
      },
      'GET /api/v1/products/p-unit/bom/explode' => {
        'product_id': 'p-unit',
        'bom_revision': 1,
        'quantity': o.queryParameters['quantity'],
        'nodes': [
          _node(null, 1, 'FRAME-A', 'pcs', '1', false),
          _node(0, 2, 'PROFILE-40', 'm', '7.15', true),
          _node(null, 1, 'PUMP-05', 'pcs', '2', true),
        ],
        'requirements': [
          {
            'product_id': 'p-PROFILE-40',
            'code': 'PROFILE-40',
            'name': 'Profile',
            'unit': 'm',
            'product_type': 'purchased',
            'quantity': '7.15',
          },
          {
            'product_id': 'p-PUMP-05',
            'code': 'PUMP-05',
            'name': 'Pump',
            'unit': 'pcs',
            'product_type': 'purchased',
            'quantity': '2',
          },
        ],
      },
      'GET /api/v1/me' => {
        'user_id': 'u',
        'email': 'admin@example.com',
        'display_name': 'Admin',
        'roles': ['admin'],
        'permissions': ['bom.read', 'bom.write'],
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
      },
      _ => null,
    };
    if (json == null) {
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

void main() {
  testWidgets(
    'shows the active revision, subassemblies and exploded requirements',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = _FakeApi();
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = fake;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dioProvider.overrideWithValue(dio)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: BomTab(product: _product)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Revision 1 · active · 2 lines'), findsOneWidget);
      expect(
        find.text('subassembly'),
        findsOneWidget,
        reason: 'FRAME-A has its own BOM',
      );
      expect(
        find.text('New revision'),
        findsOneWidget,
        reason: 'no draft yet and user may edit',
      );
      expect(
        find.text('Save draft'),
        findsNothing,
        reason: 'active revisions are read-only',
      );
      expect(
        find.text('7,15 m'),
        findsNWidgets(2),
        reason: 'structure and totals',
      );

      await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '3');
      await tester.tap(find.text('Explode'));
      await tester.pumpAndSettle();
      expect(fake.requests.last, contains('{quantity: 3}'));
    },
  );
}
