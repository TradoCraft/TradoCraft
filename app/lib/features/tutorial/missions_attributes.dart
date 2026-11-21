import 'model.dart';

/// Chapter 11: defining company-specific product properties (attribute definitions) and filling
/// them on a product (`TUT-CTRL`).

Map? _productByCode(Object? page, String code) {
  final items = page is Map ? page['items'] : null;
  if (items is! List) return null;
  for (final i in items) {
    if (i is Map && i['code'] == code) return i;
  }
  return null;
}

bool _hasDefinition(Object? json, String key, String kind) =>
    json is Map &&
    json['key'] == key &&
    json['kind'] == kind &&
    json['scope'] == 'product';

bool _listHasDefinition(Object? json, String key, String kind) =>
    json is List && json.any((item) => _hasDefinition(item, key, kind));

MissionStep _defineAttribute({
  required String id,
  required String key,
  required String label,
  required String kind,
  required int sortOrder,
  bool hasHint = false,
}) => MissionStep(
  id: id,
  hasHint: hasHint,
  route: '/admin',
  targets: const ['attrdef-save', 'attrdef-new'],
  completion: OnApi(
    'POST',
    '/attribute-definitions',
    predicate: (json, _) => _hasDefinition(json, key, kind),
  ),
  probe: Probe(
    '/api/v1/attribute-definitions',
    query: const {'scope': 'product'},
    done: (json, _) => _listHasDefinition(json, key, kind),
  ),
  assist: (host) async {
    final existing = await host.dio.get<Object?>(
      '/api/v1/attribute-definitions',
      queryParameters: const {'scope': 'product'},
    );
    if (_listHasDefinition(existing.data, key, kind)) return;
    await host.dio.post<Object?>(
      '/api/v1/attribute-definitions',
      data: {
        'key': key,
        'label': label,
        'kind': kind,
        'scope': 'product',
        'sort_order': sortOrder,
        'active': true,
      },
    );
  },
);

const _expectedControllerAttrs = <String, ({String kind, String value})>{
  'relay_count': (kind: 'number', value: '4'),
  'fet_count': (kind: 'number', value: '2'),
  'digital_inputs': (kind: 'number', value: '8'),
  'supports_24v_polarized_2wire': (kind: 'boolean', value: 'true'),
};

bool _controllerAttrsSet(Object? json, MissionContext _) {
  if (json is! List) return false;
  final byKey = <String, Map>{};
  for (final item in json) {
    if (item is Map && item['key'] is String) {
      byKey[item['key'] as String] = item;
    }
  }
  for (final entry in _expectedControllerAttrs.entries) {
    final saved = byKey[entry.key];
    if (saved == null || saved['kind'] != entry.value.kind) return false;
    final v = '${saved['value'] ?? ''}'.trim();
    if (entry.value.kind == 'number') {
      final actualNum = num.tryParse(v);
      final expectedNum = num.tryParse(entry.value.value);
      if (actualNum == null || expectedNum == null || actualNum != expectedNum) {
        return false;
      }
    } else if (v != entry.value.value) {
      return false;
    }
  }
  return true;
}

Future<void> _fillControllerAttrs(ActionHost host) async {
  final controllerId = host.context.values['controllerId'];
  if (controllerId == null) {
    throw StateError('Create or locate TUT-CTRL first.');
  }
  final existingRes = await host.dio.get<Object?>(
    '/api/v1/products/$controllerId/attributes',
  );
  final existing = existingRes.data is List
      ? (existingRes.data as List).whereType<Map>().toList()
      : <Map>[];
  final merged = <Map<String, Object?>>[
    for (final item in existing)
      if (!_expectedControllerAttrs.containsKey(item['key']))
        {
          'key': item['key'],
          'kind': item['kind'],
          'value': item['value'],
          if (item['value_min'] != null) 'value_min': item['value_min'],
          if (item['value_max'] != null) 'value_max': item['value_max'],
          if (item['unit'] != null) 'unit': item['unit'],
        },
    for (final entry in _expectedControllerAttrs.entries)
      {
        'key': entry.key,
        'kind': entry.value.kind,
        'value': entry.value.value,
      },
  ];
  await host.dio.put<Object?>(
    '/api/v1/products/$controllerId/attributes',
    data: merged,
  );
}

/// Chapter 11: defining company-specific product properties without hard-coding them.
final attributesMission = Mission(
  id: 'attributes',
  steps: [
    MissionStep(
      id: 'needs',
      route: '/products',
      probe: Probe(
        '/api/v1/products',
        query: const {'q': 'TUT-CTRL', 'limit': 20},
        done: (json, _) {
          final p = _productByCode(json, 'TUT-CTRL');
          return p != null && p['id'] is String && p['active'] != false;
        },
        capture: (json, _) {
          final p = _productByCode(json, 'TUT-CTRL');
          return p == null ? const {} : {'controllerId': '${p['id']}'};
        },
      ),
      assist: (host) async {
        final res = await host.dio.get<Object?>(
          '/api/v1/products',
          queryParameters: const {'q': 'TUT-CTRL', 'limit': 20},
        );
        if (_productByCode(res.data, 'TUT-CTRL') != null) return;
        await host.dio.post<Object?>(
          '/api/v1/products',
          data: const {
            'code': 'TUT-CTRL',
            'name': 'Controller',
            'product_type': 'purchased',
          },
        );
      },
    ),
    const MissionStep(id: 'intro'),
    const MissionStep(
      id: 'openAdmin',
      route: '/admin',
      completion: OnRoute('/admin'),
    ),
    _defineAttribute(
      id: 'relays',
      key: 'relay_count',
      label: 'Relays',
      kind: 'number',
      sortOrder: 10,
      hasHint: true,
    ),
    _defineAttribute(
      id: 'fets',
      key: 'fet_count',
      label: 'FETs',
      kind: 'number',
      sortOrder: 20,
    ),
    _defineAttribute(
      id: 'digitalInputs',
      key: 'digital_inputs',
      label: 'Digital inputs',
      kind: 'number',
      sortOrder: 30,
    ),
    _defineAttribute(
      id: 'polarized24v',
      key: 'supports_24v_polarized_2wire',
      label: '24V polarized 2-wire output',
      kind: 'boolean',
      sortOrder: 40,
    ),
    const MissionStep(
      id: 'openController',
      route: '/products/{controllerId}',
      completion: OnRoute('/products/{controllerId}'),
    ),
    const MissionStep(
      id: 'suitabilityTab',
      route: '/products/{controllerId}',
    ),
    MissionStep(
      id: 'fillProperties',
      hasHint: true,
      route: '/products/{controllerId}',
      targets: const ['suitability-save'],
      completion: const OnApi(
        'PUT',
        '/products/{controllerId}/attributes',
        predicate: _controllerAttrsSet,
      ),
      probe: Probe(
        '/api/v1/products/{controllerId}/attributes',
        done: _controllerAttrsSet,
      ),
      assist: _fillControllerAttrs,
    ),
    const MissionStep(id: 'done'),
  ],
);
