import 'missions_purchasing.dart';
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

Object? _itemWithCode(Object? page, String code, String type) {
  final items = page is Map ? page['items'] : null;
  if (items is! List) return null;
  for (final i in items) {
    if (i is Map && i['code'] == code && i['product_type'] == type) return i;
  }
  return null;
}

/// A step that creates a product with [code] of [type] and captures its id as [idKey].
MissionStep _createProduct(
  String id,
  String code,
  String type,
  String idKey, {
  bool hasHint = false,
}) => MissionStep(
  id: id,
  hasHint: hasHint,
  targets: const ['product-form-save', 'products-create'],
  route: '/products',
  completion: OnApi(
    'POST',
    '/products',
    predicate: (json, _) =>
        json is Map && json['code'] == code && json['product_type'] == type,
  ),
  capture: (json) => json is Map ? {idKey: '${json['id']}'} : const {},
  probe: Probe(
    '/api/v1/products',
    query: {'q': code, 'limit': 20},
    done: (json, _) => _itemWithCode(json, code, type) != null,
    capture: (json, _) {
      final p = _itemWithCode(json, code, type);
      return p is Map ? {idKey: '${p['id']}'} : const {};
    },
  ),
);

/// The revision of the story's product the later steps work on: its draft, else its active one,
/// else the first (from the list of revisions).
Map? _tutorialBom(Object? list) {
  if (list is! List) return null;
  final boms = list.whereType<Map>().toList();
  for (final status in ['draft', 'active']) {
    for (final b in boms) {
      if (b['status'] == status) return b;
    }
  }
  return boms.firstOrNull;
}

bool _bomHasLines(Object? json, MissionContext ctx) {
  final lines = json is Map ? json['lines'] : null;
  if (lines is! List || lines.length < 3) return false;
  final have = {
    for (final l in lines)
      if (l is Map) l['component_product_id'],
  };
  for (final k in [_motor.idKey, _frame.idKey, _controller.idKey]) {
    final id = ctx.values[k];
    if (id != null && !have.contains(id)) return false;
  }
  return true;
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
    _createProduct(
      'motor',
      _motor.code,
      'purchased',
      _motor.idKey,
      hasHint: true,
    ),
    _createProduct('frame', _frame.code, 'purchased', _frame.idKey),
    _createProduct(
      'controller',
      _controller.code,
      'purchased',
      _controller.idKey,
    ),
    _createProduct(
      'cart',
      finishedProduct.code,
      'manufactured',
      finishedProduct.idKey,
    ),
    const MissionStep(
      id: 'openCart',
      route: '/products/{cartId}',
      completion: OnRoute('/products/{cartId}'),
    ),
    const MissionStep(id: 'bomTab'),
    MissionStep(
      id: 'revision',
      targets: const ['bom-new-revision'],
      completion: const OnApi('POST', '/products/{cartId}/boms'),
      capture: (json) => json is Map ? {'bomId': '${json['id']}'} : const {},
      probe: Probe(
        '/api/v1/products/{cartId}/boms',
        done: (json, _) => _tutorialBom(json) != null,
        capture: (json, _) {
          final b = _tutorialBom(json);
          return b == null ? const {} : {'bomId': '${b['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'lines',
      hasHint: true,
      targets: const ['bom-add-component'],
      completion: const OnApi('PUT', '/boms/{bomId}', predicate: _bomHasLines),
      probe: Probe('/api/v1/boms/{bomId}', done: _bomHasLines),
    ),
    MissionStep(
      id: 'activate',
      targets: const ['bom-activate'],
      completion: const OnApi('POST', '/boms/{bomId}/activate'),
      probe: Probe(
        '/api/v1/boms/{bomId}',
        done: (json, _) => json is Map && json['status'] == 'active',
      ),
    ),
    const MissionStep(id: 'done'),
  ],
);
