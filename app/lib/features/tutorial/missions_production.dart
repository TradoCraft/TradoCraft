import 'missions_purchasing.dart';
import 'model.dart';

/// Chapters 5 and 6: manufacturing the cart, price zones and per-zone prices.

/// The code of the production division of the story.
const tutorialDivisionCode = 'TUT-ASM';

/// The code of the price zone of the story.
const tutorialZoneCode = 'TUT-EXPORT';

Map? _division(Object? list) {
  if (list is! List) return null;
  for (final d in list) {
    if (d is Map && d['code'] == tutorialDivisionCode) return d;
  }
  return null;
}

bool _hasMembers(Map? d) => d != null && d['members'] is List && (d['members'] as List).isNotEmpty;

/// The newest not cancelled production order of the cart in a production list answer.
Map? _cartOrder(Object? page, MissionContext ctx, {Set<String>? statuses}) {
  final items = page is Map ? page['items'] : null;
  if (items is! List) return null;
  for (final o in items) {
    if (o is Map &&
        o['product_id'] == ctx.values['cartId'] &&
        o['status'] != 'cancelled' &&
        (statuses == null || statuses.contains(o['status']))) {
      return o;
    }
  }
  return null;
}

bool _orderStatus(Object? json, Set<String> statuses) =>
    json is Map && statuses.contains(json['status']);

/// Chapter 5: a production division with you as member, then a production order for 5 carts,
/// started and completed.
final manufacturingMission = Mission(
  id: 'manufacturing',
  steps: [
    const MissionStep(id: 'needs', probe: productsProbe),
    const MissionStep(
      id: 'openDivisions',
      route: '/production/divisions',
      targets: ['production-divisions'],
      completion: OnRoute('/production/divisions'),
    ),
    MissionStep(
      id: 'division',
      hasHint: true,
      route: '/production/divisions',
      targets: const ['division-form-save', 'division-add'],
      completion: OnApi(
        'POST',
        '/production/divisions',
        predicate: (json, _) =>
            json is Map &&
            json['code'] == tutorialDivisionCode &&
            _hasMembers(json),
      ),
      capture: (json) => json is Map ? {'divisionId': '${json['id']}'} : const {},
      probe: Probe(
        '/api/v1/production/divisions',
        done: (json, _) => _hasMembers(_division(json)),
        capture: (json, _) {
          final d = _division(json);
          return d == null ? const {} : {'divisionId': '${d['id']}'};
        },
      ),
    ),
    const MissionStep(
      id: 'queue',
      route: '/production',
      targets: ['production-scope'],
      completion: OnRoute(r'/production(\?.*)?$'),
    ),
    MissionStep(
      id: 'release',
      hasHint: true,
      route: '/production',
      targets: const ['production-build-save', 'production-build'],
      completion: OnApi(
        'POST',
        '/production-orders',
        predicate: (json, ctx) =>
            json is Map && json['product_id'] == ctx.values['cartId'],
      ),
      capture: (json) => json is Map ? {'productionId': '${json['id']}'} : const {},
      probe: Probe(
        '/api/v1/production-orders',
        query: {'q': 'TUT-CART', 'limit': 20},
        done: (json, ctx) => _cartOrder(json, ctx) != null,
        capture: (json, ctx) {
          final o = _cartOrder(json, ctx);
          return o == null ? const {} : {'productionId': '${o['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'assign',
      route: '/production/{productionId}',
      targets: const ['production-save', 'production-division'],
      completion: OnApi(
        'PUT',
        '/production-orders/{productionId}',
        predicate: (json, ctx) =>
            json is Map && json['division_id'] == ctx.values['divisionId'],
      ),
      probe: Probe(
        '/api/v1/production-orders/{productionId}',
        done: (json, ctx) =>
            json is Map && json['division_id'] == ctx.values['divisionId'],
      ),
    ),
    MissionStep(
      id: 'start',
      route: '/production/{productionId}',
      targets: const ['production-start'],
      completion: const OnApi('POST', '/production-orders/{productionId}/start'),
      probe: Probe(
        '/api/v1/production-orders/{productionId}',
        done: (json, _) => _orderStatus(json, {'in_progress', 'completed'}),
      ),
    ),
    MissionStep(
      id: 'complete',
      hasHint: true,
      route: '/production/{productionId}',
      targets: const ['production-complete-save', 'production-complete'],
      completion: const OnApi(
        'POST',
        '/production-orders/{productionId}/complete',
      ),
      probe: Probe(
        '/api/v1/production-orders/{productionId}',
        done: (json, _) => _orderStatus(json, {'completed'}),
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

Map? _zone(Object? list) {
  if (list is! List) return null;
  for (final z in list) {
    if (z is Map && z['code'] == tutorialZoneCode) return z;
  }
  return null;
}

/// The prices of the cart that exist in [zoneId] and in at least one other zone.
bool _pricedInTwoZones(Object? json, MissionContext ctx) {
  if (json is! List) return false;
  final zones = {
    for (final p in json)
      if (p is Map) p['zone_id'],
  };
  return zones.length >= 2 && zones.contains(ctx.values['zoneId']);
}

/// Chapter 6: a price zone and a price of the cart in two zones.
final pricesMission = Mission(
  id: 'prices',
  steps: [
    const MissionStep(id: 'needs', probe: productsProbe),
    const MissionStep(
      id: 'openAdmin',
      route: '/admin',
      targets: ['user-menu'],
      completion: OnRoute('/admin'),
    ),
    MissionStep(
      id: 'zone',
      hasHint: true,
      route: '/admin',
      targets: const ['zone-form-save', 'zone-new'],
      completion: OnApi(
        'POST',
        '/price-zones',
        predicate: (json, _) => json is Map && json['code'] == tutorialZoneCode,
      ),
      capture: (json) => json is Map ? {'zoneId': '${json['id']}'} : const {},
      probe: Probe(
        '/api/v1/price-zones',
        done: (json, _) => _zone(json) != null,
        capture: (json, _) {
          final z = _zone(json);
          return z == null ? const {} : {'zoneId': '${z['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'openCart',
      route: '/products/{cartId}',
      completion: const OnRoute('/products/{cartId}'),
    ),
    MissionStep(
      id: 'priceExport',
      hasHint: true,
      route: '/products/{cartId}',
      targets: const ['price-form-save', 'price-new'],
      completion: OnApi(
        'POST',
        '/products/{cartId}/prices',
        predicate: (json, ctx) =>
            json is Map && json['zone_id'] == ctx.values['zoneId'],
      ),
      probe: Probe(
        '/api/v1/products/{cartId}/prices',
        done: (json, ctx) =>
            json is List &&
            json.any((p) => p is Map && p['zone_id'] == ctx.values['zoneId']),
      ),
    ),
    MissionStep(
      id: 'priceHome',
      route: '/products/{cartId}',
      targets: const ['price-form-save', 'price-new'],
      completion: OnApi(
        'POST',
        '/products/{cartId}/prices',
        predicate: (json, ctx) =>
            json is Map && json['zone_id'] != ctx.values['zoneId'],
      ),
      probe: const Probe(
        '/api/v1/products/{cartId}/prices',
        done: _pricedInTwoZones,
      ),
    ),
    const MissionStep(id: 'done'),
  ],
);
