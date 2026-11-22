import 'package:decimal/decimal.dart';

import 'model.dart';

Future<void> _post(ActionHost host, String path, {Object? data}) async {
  await host.dio.post<Object?>('/api/v1$path', data: data);
}

String _requiredId(ActionHost host, String key) =>
    host.context.values[key] ??
    (throw StateError('Finish the tutorial step that supplies $key first.'));

/// Chapters 2 to 4: suppliers, buying and receiving, checking the supplier invoices.

/// The code and name of the two tutorial suppliers (fictitious).
const tutorialSupplierA = (
  code: 'TUT-SUP-A',
  name: 'Voltaic Drives Ltd',
  idKey: 'supplierAId',
);

/// The second tutorial supplier.
const tutorialSupplierB = (
  code: 'TUT-SUP-B',
  name: 'Ironbridge Frames',
  idKey: 'supplierBId',
);

const _componentKeys = ['motorId', 'frameId', 'controllerId'];

Map? _byField(Object? list, String field, String value) {
  if (list is! List) return null;
  for (final i in list) {
    if (i is Map && i[field] == value) return i;
  }
  return null;
}

Map<String, String> _captureProducts(Object? page) {
  final items = page is Map ? page['items'] : null;
  final out = <String, String>{};
  for (final (code, key, expectedType) in [
    ('MOT-3P-055', 'motorId', 'purchased'),
    ('VFD-3P-055', 'frameId', 'purchased'),
    ('PLC-BASE', 'controllerId', 'purchased'),
    ('CONV-BELT-1M', 'cartId', 'manufactured'),
  ]) {
    final p = _byField(items, 'code', code);
    final id = p?['id'];
    final type = p?['product_type'];
    if (id is String &&
        id.isNotEmpty &&
        p?['active'] != false &&
        (type == null || type == expectedType)) {
      out[key] = id;
    }
  }
  return out;
}

/// A probe that finds the four core story products and captures their ids, so chapters can be
/// started on their own (the step it sits on is skipped when the products exist).
const productsProbe = Probe(
  '/api/v1/products',
  query: {'limit': 100},
  done: _allProducts,
  capture: _productsCapture,
);

bool _allProducts(Object? json, MissionContext ctx) =>
    _captureProducts(json).length == 4;

Map<String, String> _productsCapture(Object? json, MissionContext ctx) =>
    _captureProducts(json);

/// The warehouse and location the texts name: an active warehouse MAIN with an active location MAIN.
bool _isMainWarehouse(Map w) =>
    w['code'] == 'MAIN' &&
    w['kind'] != 'van' &&
    w['active'] != false &&
    w['locations'] is List &&
    (w['locations'] as List).any(
      (l) => l is Map && l['code'] == 'MAIN' && l['active'] != false,
    );

/// Whether the warehouse MAIN with its location MAIN exists and is usable. Another warehouse does not
/// count: the instructions of the later steps say "choose the location MAIN".
bool _hasReceivingLocation(Object? json, MissionContext ctx) =>
    json is List && json.any((w) => w is Map && _isMainWarehouse(w));

bool _isNewMain(Object? json, MissionContext ctx) =>
    json is Map && json['code'] == 'MAIN';

/// A read-only look at the warehouses: the steps that put goods somewhere are skipped when the
/// warehouse MAIN with its location MAIN already exists (made by hand, or by an earlier chapter).
const warehouseProbe = Probe(
  '/api/v1/inventory/warehouses',
  done: _hasReceivingLocation,
);

/// A step that creates the warehouse (a new warehouse gets its location MAIN with it). It is
/// skipped when one exists, so the same step can guard every chapter that puts goods somewhere.
const warehouseStep = MissionStep(
  id: 'warehouse',
  hasHint: true,
  route: '/stock/warehouses',
  targets: ['warehouse-form-save', 'warehouse-new'],
  // The texts of the later steps name the location MAIN, so only a warehouse MAIN finishes the step.
  completion: OnApi('POST', '/inventory/warehouses', predicate: _isNewMain),
  probe: warehouseProbe,
  assist: _createMainWarehouse,
  // Reactivating or editing the warehouse or its location can satisfy the probe as well.
  recheckOn: [
    OnApi('PUT', '/inventory/warehouses/[^/]+'),
    OnApi('PUT', '/inventory/locations/[^/]+'),
    OnApi('POST', '/inventory/locations'),
  ],
);

Future<void> _createMainWarehouse(ActionHost host) => _post(
  host,
  '/inventory/warehouses',
  data: {'code': 'MAIN', 'name': 'Main warehouse'},
);

Map<String, String> _idOf(Object? json, String key) =>
    json is Map ? {key: '${json['id']}'} : const {};

bool _isActiveSupplier(Object? supplier, String code) =>
    supplier is Map &&
    supplier['code'] == code &&
    supplier['active'] != false &&
    supplier['id'] is String &&
    (supplier['id'] as String).isNotEmpty;

/// A step that creates the supplier [s].
MissionStep _createSupplier(
  String id,
  ({String code, String name, String idKey}) s,
) => MissionStep(
  id: id,
  route: '/purchasing',
  targets: const ['supplier-form-save', 'suppliers-create'],
  completion: OnApi(
    'POST',
    '/suppliers',
    predicate: (json, _) => _isActiveSupplier(json, s.code),
  ),
  capture: (json) => _idOf(json, s.idKey),
  assist: (host) async {
    final suppliers = (await host.dio.get<Object?>('/api/v1/suppliers')).data;
    final existing = _byField(suppliers, 'code', s.code);
    if (existing != null) {
      if (existing['active'] == false) {
        throw StateError('Reactivate supplier ${s.code} in Purchasing first.');
      }
      return;
    }
    await _post(
      host,
      '/suppliers',
      data: {'code': s.code, 'name': s.name, 'country': 'BE'},
    );
  },
  probe: Probe(
    '/api/v1/suppliers',
    done: (json, _) => _isActiveSupplier(_byField(json, 'code', s.code), s.code),
    capture: (json, _) => _idOf(_byField(json, 'code', s.code), s.idKey),
  ),
  recheckOn: const [OnApi('PUT', '/suppliers/[^/]+')],
);

/// A step that gives [supplierKey] a price-list entry for [productKey].
MissionStep _price(
  String id,
  String supplierKey,
  String productKey, {
  required String unitPrice,
  required int leadDays,
  required String minimum,
  bool hasHint = false,
}) => MissionStep(
  id: id,
  hasHint: hasHint,
  route: '/suppliers/{$supplierKey}',
  targets: const ['supplier-price-save', 'supplier-price-add'],
  completion: OnApi('POST', '/suppliers/{$supplierKey}/products/{$productKey}'),
  assist: (host) {
    final supplier = _requiredId(host, supplierKey);
    final product = _requiredId(host, productKey);
    return _post(
      host,
      '/suppliers/$supplier/products/$product',
      data: {
        'unit_price': unitPrice,
        'lead_time_days': leadDays,
        'moq': minimum,
      },
    );
  },
  probe: Probe(
    '/api/v1/suppliers/{$supplierKey}/products',
    done: (json, ctx) =>
        _byField(json, 'product_id', ctx.values[productKey] ?? '') != null,
  ),
);

/// Chapter 2: two suppliers with a price list.
final suppliersMission = Mission(
  id: 'suppliers',
  steps: [
    const MissionStep(id: 'needs', probe: productsProbe),
    const MissionStep(
      id: 'open',
      route: '/purchasing',
      completion: OnRoute('/purchasing'),
    ),
    _createSupplier('supplierA', tutorialSupplierA),
    _createSupplier('supplierB', tutorialSupplierB),
    MissionStep(
      id: 'openA',
      route: '/suppliers/{supplierAId}',
      completion: const OnRoute('/suppliers/{supplierAId}'),
    ),
    _price(
      'priceMotor',
      'supplierAId',
      'motorId',
      unitPrice: '120',
      leadDays: 14,
      minimum: '5',
      hasHint: true,
    ),
    _price(
      'priceFrame',
      'supplierAId',
      'frameId',
      unitPrice: '45',
      leadDays: 10,
      minimum: '5',
    ),
    _price(
      'priceController',
      'supplierAId',
      'controllerId',
      unitPrice: '30',
      leadDays: 7,
      minimum: '5',
    ),
    MissionStep(
      id: 'openB',
      route: '/suppliers/{supplierBId}',
      completion: const OnRoute('/suppliers/{supplierBId}'),
    ),
    _price(
      'priceMotorB',
      'supplierBId',
      'motorId',
      unitPrice: '135',
      leadDays: 5,
      minimum: '1',
    ),
    const MissionStep(id: 'done'),
  ],
);

bool _poHasStatus(Object? json, Set<String> statuses) =>
    json is Map && statuses.contains(json['status']);

const _sentOrLater = {'sent', 'partially_received', 'received'};
const _approvedOrLater = {'approved', ..._sentOrLater};

bool _poHasComponents(Object? json, MissionContext ctx) {
  final lines = json is Map ? json['lines'] : null;
  if (lines is! List) return false;
  final have = {
    for (final l in lines)
      if (l is Map) l['product_id'],
  };
  for (final k in _componentKeys) {
    final id = ctx.values[k];
    if (id != null && !have.contains(id)) return false;
  }
  return lines.length >= 3;
}

bool _isTutorialOrder(Object? order, MissionContext ctx) {
  if (order is! Map ||
      order['id'] is! String ||
      ctx.values[tutorialSupplierA.idKey] == null ||
      order['supplier_id'] != ctx.values[tutorialSupplierA.idKey] ||
      order['status'] == 'cancelled') {
    return false;
  }
  final lines = order['lines'];
  if (lines is! List || lines.length != _componentKeys.length) return false;
  final expected = _componentKeys.map((key) => ctx.values[key]).toSet();
  return !expected.contains(null) &&
      expected.length == lines.length &&
      lines.every(
        (l) =>
            l is Map &&
            expected.remove(l['product_id']) &&
            num.tryParse('${l['quantity']}') == 30,
      );
}

Map? _tutorialOrder(Object? list, MissionContext ctx) {
  if (list is! List) return null;
  return list.whereType<Map>().where((o) => _isTutorialOrder(o, ctx)).firstOrNull;
}

List<String> _purchaseOrderDetails(Object? list, MissionContext ctx) => [
  if (list is List)
    for (final o in list)
      if (o is Map && o['status'] != 'cancelled' && o['id'] is String)
        '/api/v1/purchase-orders/${o['id']}',
];

Future<void> _createTutorialOrder(ActionHost host) async {
  final supplier = _requiredId(host, tutorialSupplierA.idKey);
  final prices = (await host.dio.get<Object?>(
    '/api/v1/suppliers/$supplier/products',
  )).data;
  final lines = <Map<String, Object?>>[];
  for (final key in _componentKeys) {
    final product = _requiredId(host, key);
    final price = _byField(prices, 'product_id', product);
    if (price == null) {
      throw StateError(
        'Add all three tutorial prices for Voltaic Drives Ltd first.',
      );
    }
    lines.add({
      'product_id': product,
      'quantity': '30',
      'unit_price': price['unit_price'],
      'supplier_product_code': price['supplier_product_code'],
    });
  }
  await _post(
    host,
    '/purchase-orders',
    data: {'supplier_id': supplier, 'lines': lines},
  );
}

Future<Map<String, dynamic>> _getTutorialOrder(ActionHost host) async {
  final orderPath = '/purchase-orders/${_requiredId(host, 'poId')}';
  final order = (await host.dio.get<Map<String, dynamic>>('/api/v1$orderPath'))
      .data;
  if (order == null || !_isTutorialOrder(order, host.context)) {
    throw StateError(
      'Use the tutorial purchase order with 30 of each component or complete this step by hand.',
    );
  }
  return order;
}

Future<void> _approveTutorialOrder(ActionHost host) async {
  final order = await _getTutorialOrder(host);
  await _post(host, '/purchase-orders/${order['id']}/approve');
}

Future<void> _sendTutorialOrder(ActionHost host) async {
  final order = await _getTutorialOrder(host);
  await _post(host, '/purchase-orders/${order['id']}/send');
}

Future<void> _receiveRemainingGoods(ActionHost host) async {
  final order = await _getTutorialOrder(host);
  final warehouses = (await host.dio.get<List<dynamic>>(
    '/api/v1/inventory/warehouses',
  )).data;
  final warehouse = warehouses
      ?.whereType<Map>()
      .where(_isMainWarehouse)
      .firstOrNull;
  if (warehouse == null) {
    throw StateError(
      'Create or reactivate the MAIN warehouse and location first.',
    );
  }
  final location = (warehouse['locations'] as List).whereType<Map>().firstWhere(
    (l) => l['code'] == 'MAIN' && l['active'] != false,
  );
  final lines = <Map<String, Object?>>[];
  for (final line in (order['lines'] as List).cast<Map>()) {
    final remaining =
        Decimal.parse('${line['quantity']}') -
        Decimal.parse('${line['quantity_received']}');
    if (remaining > Decimal.zero) {
      lines.add({'po_line_id': line['id'], 'quantity': remaining.toString()});
    }
  }
  if (lines.isEmpty) return;
  await _post(
    host,
    '/purchase-orders/${order['id']}/receipts',
    data: {
      'warehouse_id': warehouse['id'],
      'location_id': location['id'],
      'lines': lines,
    },
  );
}

/// Chapter 3: a purchase order, approved, sent, received in two steps; then the stock.
final buyingMission = Mission(
  id: 'buying',
  steps: [
    const MissionStep(id: 'needs', probe: productsProbe),
    const MissionStep(
      id: 'open',
      route: '/purchasing',
      completion: OnRoute('/purchasing'),
    ),
    MissionStep(
      id: 'order',
      hasHint: true,
      route: '/purchasing',
      targets: const ['po-form-save', 'po-create'],
      completion: OnApi(
        'POST',
        '/purchase-orders',
        predicate: (json, ctx) =>
            json is Map &&
            json['supplier_id'] == ctx.values[tutorialSupplierA.idKey] &&
            _poHasComponents(json, ctx),
      ),
      capture: (json) => _idOf(json, 'poId'),
      assist: _createTutorialOrder,
      probe: Probe(
        '/api/v1/purchase-orders',
        query: {'supplier_id': '{supplierAId}'},
        expand: _purchaseOrderDetails,
        done: (json, ctx) => _tutorialOrder(json, ctx) != null,
        capture: (json, ctx) {
          final o = _tutorialOrder(json, ctx);
          return o == null ? const {} : {'poId': '${o['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'openOrder',
      route: '/purchase-orders/{poId}',
      completion: const OnRoute('/purchase-orders/{poId}'),
    ),
    MissionStep(
      id: 'approve',
      route: '/purchase-orders/{poId}',
      targets: const ['po-approve'],
      completion: const OnApi('POST', '/purchase-orders/{poId}/approve'),
      assist: _approveTutorialOrder,
      probe: Probe(
        '/api/v1/purchase-orders/{poId}',
        done: (json, _) => _poHasStatus(json, _approvedOrLater),
      ),
    ),
    MissionStep(
      id: 'send',
      route: '/purchase-orders/{poId}',
      targets: const ['po-send'],
      completion: const OnApi('POST', '/purchase-orders/{poId}/send'),
      assist: _sendTutorialOrder,
      probe: Probe(
        '/api/v1/purchase-orders/{poId}',
        done: (json, _) => _poHasStatus(json, _sentOrLater),
      ),
    ),
    const MissionStep(
      id: 'openWarehouses',
      route: '/stock/warehouses',
      targets: ['stock-warehouses'],
      completion: OnRoute('/stock/warehouses'),
      probe: warehouseProbe,
    ),
    warehouseStep,
    MissionStep(
      id: 'receivePart',
      hasHint: true,
      route: '/purchase-orders/{poId}',
      targets: const ['po-receive-submit', 'po-receive'],
      completion: const OnApi('POST', '/purchase-orders/{poId}/receipts'),
      probe: Probe(
        '/api/v1/purchase-orders/{poId}',
        done: (json, _) =>
            _poHasStatus(json, {'partially_received', 'received'}),
      ),
    ),
    MissionStep(
      id: 'receiveRest',
      route: '/purchase-orders/{poId}',
      targets: const ['po-receive-submit', 'po-receive'],
      completion: const OnApi('POST', '/purchase-orders/{poId}/receipts'),
      assist: _receiveRemainingGoods,
      probe: Probe(
        '/api/v1/purchase-orders/{poId}',
        done: (json, _) => _poHasStatus(json, {'received'}),
      ),
    ),
    const MissionStep(
      id: 'stock',
      route: '/stock',
      completion: OnRoute('/stock'),
    ),
    const MissionStep(id: 'done'),
  ],
);

Map? _invoiceWhere(Object? page, bool Function(Map) test) {
  final items = page is Map ? page['items'] : null;
  if (items is! List) return null;
  for (final i in items) {
    if (i is Map && test(i)) return i;
  }
  return null;
}

bool _invStatus(Object? json, Set<String> statuses) =>
    json is Map && statuses.contains(json['status']);

/// The number the story gives the second (suspicious) supplier invoice.
const tutorialInvoice2Number = 'TUT-INV-002';

Map? _secondInvoice(Object? page) =>
    _invoiceWhere(page, (i) => i['invoice_number'] == tutorialInvoice2Number);

/// Chapter 4: two supplier invoices, the three-way match, approve, dispute, pay.
final invoicesMission = Mission(
  id: 'invoices',
  steps: [
    MissionStep(
      id: 'needs',
      probe: Probe(
        '/api/v1/purchase-orders/{poId}',
        done: (json, _) => _poHasStatus(json, {'received'}),
      ),
    ),
    MissionStep(
      id: 'openOrder',
      route: '/purchase-orders/{poId}',
      completion: const OnRoute('/purchase-orders/{poId}'),
    ),
    MissionStep(
      id: 'create',
      route: '/purchase-orders/{poId}',
      hasHint: true,
      targets: const ['inv-form-save', 'po-create-invoice'],
      completion: OnApi(
        'POST',
        '/supplier-invoices',
        predicate: (json, ctx) =>
            json is Map && json['purchase_order_id'] == ctx.values['poId'],
      ),
      capture: (json) => _idOf(json, 'invoiceId'),
      probe: Probe(
        '/api/v1/supplier-invoices',
        query: {'purchase_order_id': '{poId}'},
        done: (json, _) => _invoiceWhere(json, (_) => true) != null,
        capture: (json, _) {
          final i = _invoiceWhere(json, (_) => true);
          return i == null ? const {} : {'invoiceId': '${i['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'match',
      route: '/supplier-invoices/{invoiceId}',
      targets: const ['inv-match-banner'],
    ),
    MissionStep(
      id: 'approve',
      route: '/supplier-invoices/{invoiceId}',
      targets: const ['inv-approve'],
      completion: const OnApi('POST', '/supplier-invoices/{invoiceId}/approve'),
      probe: Probe(
        '/api/v1/supplier-invoices/{invoiceId}',
        done: (json, _) => _invStatus(json, {'approved', 'paid'}),
      ),
    ),
    MissionStep(
      id: 'second',
      hasHint: true,
      route: '/finance',
      targets: const ['inv-form-save'],
      completion: OnApi(
        'POST',
        '/supplier-invoices',
        predicate: (json, _) =>
            json is Map && json['invoice_number'] == tutorialInvoice2Number,
      ),
      capture: (json) => _idOf(json, 'invoice2Id'),
      probe: Probe(
        '/api/v1/supplier-invoices',
        query: {'supplier_id': '{supplierAId}'},
        done: (json, _) => _secondInvoice(json) != null,
        capture: (json, _) {
          final i = _secondInvoice(json);
          return i == null ? const {} : {'invoice2Id': '${i['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'openSecond',
      route: '/supplier-invoices/{invoice2Id}',
      completion: const OnRoute('/supplier-invoices/{invoice2Id}'),
    ),
    MissionStep(
      id: 'mismatch',
      route: '/supplier-invoices/{invoice2Id}',
      targets: const ['inv-match-banner'],
    ),
    MissionStep(
      id: 'dispute',
      route: '/supplier-invoices/{invoice2Id}',
      targets: const ['inv-dispute'],
      completion: const OnApi('POST', '/supplier-invoices/{invoice2Id}/dispute'),
      probe: Probe(
        '/api/v1/supplier-invoices/{invoice2Id}',
        done: (json, _) => _invStatus(json, {'disputed'}),
      ),
    ),
    const MissionStep(id: 'tolerances', route: '/finance'),
    MissionStep(
      id: 'pay',
      route: '/supplier-invoices/{invoiceId}',
      targets: const ['inv-mark-paid'],
      completion: const OnApi('POST', '/supplier-invoices/{invoiceId}/mark-paid'),
      probe: Probe(
        '/api/v1/supplier-invoices/{invoiceId}',
        done: (json, _) => _invStatus(json, {'paid'}),
      ),
    ),
    const MissionStep(id: 'done'),
  ],
);
