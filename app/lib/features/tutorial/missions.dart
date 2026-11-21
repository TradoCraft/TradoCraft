import 'missions_helpdesk.dart';
import 'missions_production.dart';
import 'missions_purchasing.dart';
import 'missions_sales.dart';
import 'model.dart';

/// The chapters of the tutorial, in order. To add a chapter: append a [Mission] here, add its
/// strings (see `strings.dart`, the five ARB files) and, where a step points at a widget, wrap
/// that widget in a `TutorialTarget` with the step's `targetId`.
final List<Mission> allMissions = [
  welcomeMission,
  productMission,
  suppliersMission,
  buyingMission,
  invoicesMission,
  manufacturingMission,
  pricesMission,
  customerMission,
  quotationMission,
  changeMission,
  helpdeskMission,
];

/// Chapter 0: what the banner means, how tabs and the tutorial controls work.
const welcomeMission = Mission(
  id: 'welcome',
  steps: [
    MissionStep(id: 'banner', targets: ['env-banner']),
    MissionStep(id: 'tabs'),
    MissionStep(id: 'controls'),
    MissionStep(id: 'menu', targets: ['user-menu']),
    MissionStep(
      id: 'products',
      route: '/products',
      completion: OnRoute('/products'),
    ),
  ],
);

const _motor = (code: 'TUT-MOTOR', name: 'Motor', idKey: 'motorId');
const _frame = (code: 'TUT-FRAME', name: 'Frame', idKey: 'frameId');
const _controller = (
  code: 'TUT-CTRL',
  name: 'Controller',
  idKey: 'controllerId',
);

/// The code and name of the finished product of the story.
const finishedProduct = (code: 'TUT-CART', name: 'Cart', idKey: 'cartId');

Map? _productWithCode(Object? page, String code) {
  final items = page is Map ? page['items'] : null;
  if (items is! List) return null;
  for (final i in items) {
    if (i is Map && i['code'] == code) return i;
  }
  return null;
}

bool _isUsableProduct(Object? json, String code, String type) =>
    json is Map &&
    json['code'] == code &&
    json['product_type'] == type &&
    json['id'] is String &&
    json['active'] != false;

/// A step that creates a product with [code] of [type] and captures its id as [idKey].
MissionStep _createProduct(
  String id,
  ({String code, String name, String idKey}) product,
  String type, {
  bool hasHint = false,
}) => MissionStep(
  id: id,
  hasHint: hasHint,
  targets: const ['product-form-save', 'products-create'],
  route: '/products',
  completion: OnApi(
    'POST',
    '/products',
    predicate: (json, _) => _isUsableProduct(json, product.code, type),
  ),
  recheckOn: const [OnApi('PUT', '/products/[^/]+')],
  capture: (json) => json is Map ? {product.idKey: '${json['id']}'} : const {},
  probe: Probe(
    '/api/v1/products',
    query: {'q': product.code, 'limit': 20},
    done: (json, _) => _isUsableProduct(
      _productWithCode(json, product.code),
      product.code,
      type,
    ),
    capture: (json, _) {
      final p = _productWithCode(json, product.code);
      return p == null ? const {} : {product.idKey: '${p['id']}'};
    },
  ),
  assist: (host) async {
    final response = await host.dio.get<Object?>(
      '/api/v1/products',
      queryParameters: {'q': product.code, 'limit': 20},
    );
    final existing = _productWithCode(response.data, product.code);
    if (existing != null) {
      if (existing['product_type'] != type || existing['active'] == false) {
        throw StateError(
          'Edit ${product.code} so its type is $type and Active is on.',
        );
      }
      return;
    }
    await host.dio.post<Object?>(
      '/api/v1/products',
      data: {'code': product.code, 'name': product.name, 'product_type': type},
    );
  },
);

/// A story draft, or an active revision that already contains the three tutorial components.
Map? _tutorialBom(Object? details, MissionContext ctx) {
  if (details is! List) return null;
  final boms = details.whereType<Map>();
  return boms.where((b) => b['status'] == 'draft').firstOrNull ??
      boms
          .where((b) => b['status'] == 'active' && _bomHasLines(b, ctx))
          .firstOrNull;
}

final _componentIdKeys = [_motor.idKey, _frame.idKey, _controller.idKey];

bool _bomHasLines(Object? json, MissionContext ctx) {
  final lines = json is Map ? json['lines'] : null;
  if (lines is! List || lines.length < 3) return false;
  final have = {
    for (final l in lines)
      if (l is Map) l['component_product_id'],
  };
  return _componentIdKeys.every(
    (key) => ctx.values[key] != null && have.contains(ctx.values[key]),
  );
}

Future<Map<String, dynamic>> _readStoryDraft(ActionHost host) async {
  final bomId = host.context.values['bomId'];
  final cartId = host.context.values[finishedProduct.idKey];
  if (bomId == null || cartId == null) {
    throw StateError('Create the tutorial cart and its BOM revision first.');
  }
  final response = await host.dio.get<Map<String, dynamic>>(
    '/api/v1/boms/$bomId',
  );
  final bom = response.data;
  if (bom == null || bom['product_id'] != cartId || bom['status'] != 'draft') {
    throw StateError('Open a draft BOM for the tutorial cart.');
  }
  return bom;
}

Future<void> _addBomComponents(ActionHost host) async {
  final bom = await _readStoryDraft(host);
  final ids = _componentIdKeys.map((key) => host.context.values[key]).toList();
  if (ids.contains(null)) {
    throw StateError('Create all three tutorial components first.');
  }
  final savedLines = (bom['lines'] as List).cast<Map>();
  final existingIds = savedLines
      .map((line) => line['component_product_id'])
      .toSet();
  await host.dio.put<Object?>(
    '/api/v1/boms/${bom['id']}',
    data: {
      'notes': bom['notes'],
      'lines': [
        for (final line in savedLines)
          {
            'component_product_id': line['component_product_id'],
            'quantity': line['quantity'],
            'scrap_percent': line['scrap_percent'] ?? '0',
            'notes': line['notes'] ?? '',
          },
        for (final id in ids)
          if (!existingIds.contains(id))
            {'component_product_id': id, 'quantity': '1'},
      ],
    },
  );
}

Future<void> _activateStoryBom(ActionHost host) async {
  final bom = await _readStoryDraft(host);
  if (!_bomHasLines(bom, host.context)) {
    throw StateError('Add the three tutorial components to the draft first.');
  }
  await host.dio.post<Object?>('/api/v1/boms/${bom['id']}/activate');
}

/// Chapter 1: three component products, a finished product and its bill of materials.
final productMission = Mission(
  id: 'product',
  steps: [
    const MissionStep(
      id: 'open',
      route: '/products',
      completion: OnRoute('/products'),
    ),
    _createProduct('motor', _motor, 'purchased', hasHint: true),
    _createProduct('frame', _frame, 'purchased'),
    _createProduct('controller', _controller, 'purchased'),
    _createProduct('cart', finishedProduct, 'manufactured'),
    const MissionStep(
      id: 'openCart',
      route: '/products/{cartId}',
      completion: OnRoute('/products/{cartId}'),
    ),
    const MissionStep(id: 'bomTab', route: '/products/{cartId}'),
    MissionStep(
      id: 'revision',
      route: '/products/{cartId}',
      targets: const ['bom-new-revision'],
      completion: const OnApi('POST', '/products/{cartId}/boms'),
      capture: (json) => json is Map ? {'bomId': '${json['id']}'} : const {},
      probe: Probe(
        '/api/v1/products/{cartId}/boms',
        expand: (json, _) {
          if (json is! List) return const [];
          final revisions = json.whereType<Map>();
          final draft = revisions
              .where((b) => b['status'] == 'draft')
              .firstOrNull;
          final active = revisions
              .where((b) => b['status'] == 'active')
              .firstOrNull;
          final revision = draft ?? active;
          return revision == null
              ? const []
              : ['/api/v1/boms/${revision['id']}'];
        },
        done: (json, ctx) => _tutorialBom(json, ctx) != null,
        capture: (json, ctx) {
          final b = _tutorialBom(json, ctx);
          return b == null ? const {} : {'bomId': '${b['id']}'};
        },
      ),
      assist: (host) async {
        final cartId = host.context.values[finishedProduct.idKey];
        if (cartId == null) throw StateError('Create the tutorial cart first.');
        await host.dio.post<Object?>('/api/v1/products/$cartId/boms', data: {});
      },
    ),
    MissionStep(
      id: 'lines',
      route: '/products/{cartId}',
      hasHint: true,
      targets: const ['bom-add-component'],
      completion: const OnApi('PUT', '/boms/{bomId}', predicate: _bomHasLines),
      probe: Probe('/api/v1/boms/{bomId}', done: _bomHasLines),
      assist: _addBomComponents,
    ),
    MissionStep(
      id: 'activate',
      route: '/products/{cartId}',
      targets: const ['bom-activate'],
      completion: const OnApi('POST', '/boms/{bomId}/activate'),
      probe: Probe(
        '/api/v1/boms/{bomId}',
        done: (json, _) => json is Map && json['status'] == 'active',
      ),
      assist: _activateStoryBom,
    ),
    const MissionStep(id: 'done'),
  ],
);
