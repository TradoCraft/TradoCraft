import 'model.dart';

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
  for (final (code, key) in [
    ('TUT-MOTOR', 'motorId'),
    ('TUT-FRAME', 'frameId'),
    ('TUT-CTRL', 'controllerId'),
    ('TUT-CART', 'cartId'),
  ]) {
    final p = _byField(items, 'code', code);
    if (p != null) out[key] = '${p['id']}';
  }
  return out;
}

/// A probe that finds the four products of chapter 1 and captures their ids, so chapters can be
/// started on their own (the step it sits on is skipped when the products exist).
const productsProbe = Probe(
  '/api/v1/products',
  query: {'q': 'TUT-', 'limit': 50},
  done: _allProducts,
  capture: _productsCapture,
);

bool _allProducts(Object? json, MissionContext ctx) =>
    _captureProducts(json).length == 4;

Map<String, String> _productsCapture(Object? json, MissionContext ctx) =>
    _captureProducts(json);

Map<String, String> _idOf(Object? json, String key) =>
    json is Map ? {key: '${json['id']}'} : const {};

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
    predicate: (json, _) => json is Map && json['code'] == s.code,
  ),
  capture: (json) => _idOf(json, s.idKey),
  probe: Probe(
    '/api/v1/suppliers',
    done: (json, _) => _byField(json, 'code', s.code) != null,
    capture: (json, _) {
      final f = _byField(json, 'code', s.code);
      return f == null ? const {} : {s.idKey: '${f['id']}'};
    },
  ),
);

/// A step that gives [supplierKey] a price-list entry for [productKey].
MissionStep _price(
  String id,
  String supplierKey,
  String productKey, {
  bool hasHint = false,
}) => MissionStep(
  id: id,
  hasHint: hasHint,
  route: '/suppliers/{$supplierKey}',
  targets: const ['supplier-price-save', 'supplier-price-add'],
  completion: OnApi('POST', '/suppliers/{$supplierKey}/products/{$productKey}'),
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
    _price('priceMotor', 'supplierAId', 'motorId', hasHint: true),
    _price('priceFrame', 'supplierAId', 'frameId'),
    _price('priceController', 'supplierAId', 'controllerId'),
    MissionStep(
      id: 'openB',
      route: '/suppliers/{supplierBId}',
      completion: const OnRoute('/suppliers/{supplierBId}'),
    ),
    _price('priceMotorB', 'supplierBId', 'motorId'),
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

Map? _activeOrder(Object? list) {
  if (list is! List) return null;
  for (final o in list) {
    if (o is Map && o['status'] != 'cancelled') return o;
  }
  return null;
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
      probe: Probe(
        '/api/v1/purchase-orders',
        query: {'supplier_id': '{supplierAId}'},
        done: (json, _) => _activeOrder(json) != null,
        capture: (json, _) {
          final o = _activeOrder(json);
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
      probe: Probe(
        '/api/v1/purchase-orders/{poId}',
        done: (json, _) => _poHasStatus(json, _sentOrLater),
      ),
    ),
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
