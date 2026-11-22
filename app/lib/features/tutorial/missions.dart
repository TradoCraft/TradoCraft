import 'missions_attributes.dart';
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
  conveyorsMission,
  plcMission,
  displaysMission,
  sensorsMission,
  suppliersMission,
  buyingMission,
  invoicesMission,
  manufacturingMission,
  pricesMission,
  customerMission,
  quotationMission,
  changeMission,
  helpdeskMission,
  attributesMission,
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

const _motor1p = (
  code: 'MOT-1P-037',
  name: 'Single-Phase AC Motor',
  idKey: 'motor1pId',
);
const _motor3p = (
  code: 'MOT-3P-055',
  name: '3-Phase AC Motor',
  idKey: 'motorId',
);
const _vfd = (
  code: 'VFD-3P-055',
  name: 'Variable Frequency Drive',
  idKey: 'frameId',
);
const _plcBase = (
  code: 'PLC-BASE',
  name: 'Standard PLC (10 Outputs)',
  idKey: 'controllerId',
);
const _plcLic30 = (
  code: 'PLC-LIC-30',
  name: 'PLC 30-Output Parallel License',
  idKey: 'plcLic30Id',
);
const _plcLic50 = (
  code: 'PLC-LIC-50',
  name: 'PLC 50-Output Parallel License',
  idKey: 'plcLic50Id',
);
const _plcLic100 = (
  code: 'PLC-LIC-100',
  name: 'PLC 100-Output Parallel License',
  idKey: 'plcLic100Id',
);
const _plcExpansion = (
  code: 'PLC-EXP-RS485',
  name: 'RS-485 I/O Expansion Module',
  idKey: 'plcExpId',
);
const _plcMaster = (
  code: 'PLC-MASTER',
  name: 'Master Network Controller',
  idKey: 'plcMasterId',
);
const _display = (
  code: 'DISP-RS485',
  name: 'RS-485 Operator Display',
  idKey: 'displayId',
);
const _i2cSwipe = (
  code: 'MOD-I2C-SWIPE',
  name: 'I2C Swipe Card Reader',
  idKey: 'i2cSwipeId',
);
const _i2cTemp = (
  code: 'SENS-I2C-TEMP',
  name: 'I2C Temperature Sensor',
  idKey: 'i2cTempId',
);
const _irSensor = (
  code: 'SENS-IR-24V',
  name: 'IR Photoelectric Sensor',
  idKey: 'irSensorId',
);
const _analogSensor = (
  code: 'SENS-420MA',
  name: '4-20 mA Analog Sensor',
  idKey: 'analogSensorId',
);
const _solPush = (
  code: 'SOL-PUSH',
  name: 'PowerFET Solenoid Pusher',
  idKey: 'solPushId',
);
const _solLabel = (
  code: 'SOL-LABEL',
  name: 'PowerFET Label Stamper',
  idKey: 'solLabelId',
);

/// The code and name of the finished conveyor assembly of the story.
const finishedProduct = (
  code: 'CONV-BELT-1M',
  name: 'Conveyor Belt Assembly',
  idKey: 'cartId',
);

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

final _conveyorComponentKeys = [_motor3p.idKey, _vfd.idKey];

bool _bomHasLines(Object? json, MissionContext ctx) {
  final lines = json is Map ? json['lines'] : null;
  if (lines is! List || lines.length < _conveyorComponentKeys.length) {
    return false;
  }
  final have = {
    for (final l in lines)
      if (l is Map) l['component_product_id'],
  };
  return _conveyorComponentKeys.every(
    (key) => ctx.values[key] != null && have.contains(ctx.values[key]),
  );
}

Map? _tutorialBom(Object? details, MissionContext ctx) {
  if (details is! List) return null;
  final boms = details.whereType<Map>();
  return boms.where((b) => b['status'] == 'draft').firstOrNull ??
      boms
          .where((b) => b['status'] == 'active' && _bomHasLines(b, ctx))
          .firstOrNull;
}

Future<Map<String, dynamic>> _readStoryDraft(ActionHost host) async {
  final bomId = host.context.values['bomId'];
  final cartId = host.context.values[finishedProduct.idKey];
  if (bomId == null || cartId == null) {
    throw StateError('Create the conveyor assembly and its BOM revision first.');
  }
  final response = await host.dio.get<Map<String, dynamic>>(
    '/api/v1/boms/$bomId',
  );
  final bom = response.data;
  if (bom == null || bom['product_id'] != cartId || bom['status'] != 'draft') {
    throw StateError('Open a draft BOM for the conveyor assembly.');
  }
  return bom;
}

Future<void> _addBomComponents(ActionHost host) async {
  final bom = await _readStoryDraft(host);
  final ids = _conveyorComponentKeys
      .map((key) => host.context.values[key])
      .toList();
  if (ids.contains(null)) {
    throw StateError('Create the motor and VFD components first.');
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
    throw StateError('Add the motor and VFD to the draft BOM first.');
  }
  await host.dio.post<Object?>('/api/v1/boms/${bom['id']}/activate');
}

/// Chapter 1: conveyor belts, 1-phase & 3-phase motors, VFD, SVG assembly preview and BOM.
final conveyorsMission = Mission(
  id: 'conveyors',
  steps: [
    const MissionStep(
      id: 'open',
      route: '/products',
      completion: OnRoute('/products'),
    ),
    _createProduct('motor1p', _motor1p, 'purchased'),
    _createProduct('motor', _motor3p, 'purchased', hasHint: true),
    _createProduct('vfd', _vfd, 'purchased'),
    _createProduct('conveyor', finishedProduct, 'manufactured'),
    const MissionStep(
      id: 'openConveyor',
      route: '/products/{cartId}',
      completion: OnRoute('/products/{cartId}'),
    ),
    const MissionStep(id: 'svgPreview', route: '/products/{cartId}'),
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
        if (cartId == null) {
          throw StateError('Create the conveyor assembly first.');
        }
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

/// Chapter 2: PLCs, parallel output licensing (10 -> 30 / 50 / 100), RS-485 expansion, and master controller.
final plcMission = Mission(
  id: 'plc',
  steps: [
    const MissionStep(
      id: 'open',
      route: '/products',
      completion: OnRoute('/products'),
    ),
    _createProduct('base', _plcBase, 'purchased', hasHint: true),
    _createProduct('lic30', _plcLic30, 'service'),
    _createProduct('lic50', _plcLic50, 'service'),
    _createProduct('lic100', _plcLic100, 'service'),
    _createProduct('expansion', _plcExpansion, 'purchased'),
    _createProduct('master', _plcMaster, 'purchased'),
    const MissionStep(id: 'done'),
  ],
);

/// Chapter 3: RS-485 displays and I2C peripherals (swipe card & temperature sensor).
final displaysMission = Mission(
  id: 'displays',
  steps: [
    const MissionStep(
      id: 'open',
      route: '/products',
      completion: OnRoute('/products'),
    ),
    _createProduct('display', _display, 'purchased', hasHint: true),
    _createProduct('swipe', _i2cSwipe, 'purchased'),
    _createProduct('temp', _i2cTemp, 'purchased'),
    const MissionStep(id: 'done'),
  ],
);

/// Chapter 4: IR and 4-20 mA sensors plus PowerFET-driven solenoid devices.
final sensorsMission = Mission(
  id: 'sensors',
  steps: [
    const MissionStep(
      id: 'open',
      route: '/products',
      completion: OnRoute('/products'),
    ),
    _createProduct('ir', _irSensor, 'purchased', hasHint: true),
    _createProduct('analog', _analogSensor, 'purchased'),
    _createProduct('pusher', _solPush, 'purchased'),
    _createProduct('labeler', _solLabel, 'purchased'),
    const MissionStep(id: 'done'),
  ],
);
