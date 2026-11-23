import 'model.dart';

/// Chapter 14: defining company-specific product properties (attribute definitions) and filling
/// them on the standard PLC (`PLC-BASE`).

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
    json['scope'] == 'product' &&
    json['active'] == true;

Map? _findDefinition(Object? json, String key, String kind) {
  if (json is! List) return null;
  for (final item in json) {
    if (item is Map &&
        item['key'] == key &&
        item['kind'] == kind &&
        item['scope'] == 'product') {
      return item;
    }
  }
  return null;
}

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
    final existingRes = await host.dio.get<Object?>(
      '/api/v1/attribute-definitions',
      queryParameters: const {'scope': 'product'},
    );
    final existing = _findDefinition(existingRes.data, key, kind);
    if (existing != null) {
      if (existing['active'] == true) return;
      await host.dio.put<Object?>(
        '/api/v1/attribute-definitions/${existing['id']}',
        data: {
          'key': existing['key'],
          'label': existing['label'],
          'kind': existing['kind'],
          if (existing['unit'] != null) 'unit': existing['unit'],
          if (existing['options'] != null) 'options': existing['options'],
          'scope': existing['scope'],
          'sort_order': existing['sort_order'] ?? sortOrder,
          'active': true,
        },
      );
      return;
    }
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
  'fet_count': (kind: 'number', value: '6'),
  'digital_inputs': (kind: 'number', value: '8'),
  'analog_4_20ma_inputs': (kind: 'number', value: '2'),
  'rs485_ports': (kind: 'number', value: '2'),
  'i2c_bus': (kind: 'boolean', value: 'true'),
  'licensed_outputs_tier': (kind: 'number', value: '10'),
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
    throw StateError('Create or locate PLC-BASE first.');
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

/// Chapter 14: defining company-specific PLC properties without hard-coding them.
final attributesMission = Mission(
  id: 'attributes',
  steps: [
    MissionStep(
      id: 'needs',
      route: '/products',
      recheckOn: const [
        OnApi('POST', '/products'),
        OnApi('PUT', '/products/[^/]+'),
      ],
      probe: Probe(
        '/api/v1/products',
        query: const {'q': 'PLC-BASE', 'limit': 20},
        done: (json, _) {
          final p = _productByCode(json, 'PLC-BASE');
          return p != null && p['id'] is String && p['active'] != false;
        },
        capture: (json, _) {
          final p = _productByCode(json, 'PLC-BASE');
          return p == null ? const {} : {'controllerId': '${p['id']}'};
        },
      ),
      assist: (host) async {
        final res = await host.dio.get<Object?>(
          '/api/v1/products',
          queryParameters: const {'q': 'PLC-BASE', 'limit': 20},
        );
        final existing = _productByCode(res.data, 'PLC-BASE');
        if (existing != null) {
          if (existing['active'] == false) {
            throw StateError('Edit PLC-BASE so Active is on.');
          }
          return;
        }
        await host.dio.post<Object?>(
          '/api/v1/products',
          data: const {
            'code': 'PLC-BASE',
            'name': 'Standard PLC (10 Outputs)',
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
      label: 'Relay outputs',
      kind: 'number',
      sortOrder: 10,
      hasHint: true,
    ),
    _defineAttribute(
      id: 'fets',
      key: 'fet_count',
      label: 'PowerFET outputs',
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
      id: 'analog420',
      key: 'analog_4_20ma_inputs',
      label: '4-20 mA analog inputs',
      kind: 'number',
      sortOrder: 40,
    ),
    _defineAttribute(
      id: 'rs485Ports',
      key: 'rs485_ports',
      label: 'RS-485 ports',
      kind: 'number',
      sortOrder: 50,
    ),
    _defineAttribute(
      id: 'i2cBus',
      key: 'i2c_bus',
      label: 'I2C peripheral bus',
      kind: 'boolean',
      sortOrder: 60,
    ),
    _defineAttribute(
      id: 'licensedOutputs',
      key: 'licensed_outputs_tier',
      label: 'Licensed outputs tier',
      kind: 'number',
      sortOrder: 70,
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
