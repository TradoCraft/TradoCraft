import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/products/bom_tab.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

const _product = Product(
  id: 'p-unit',
  code: 'FRAME-A',
  name: 'Frame assembly',
  description: '',
  unit: 'pcs',
  productType: 'manufactured',
  vatRate: '21',
  tracking: 'none',
  pricingType: 'list',
  active: true,
);

Map<String, Object?> _bom(String status, {int revision = 2}) => {
  'id': 'b$revision',
  'product_id': 'p-unit',
  'product_code': 'FRAME-A',
  'product_name': 'Frame assembly',
  'revision': revision,
  'status': status,
  'notes': '',
  'created_at': '2099-01-01T10:00:00Z',
  'activated_at': status == 'draft' ? null : '2099-01-02T10:00:00Z',
  'lines': [
    {
      'position': 1,
      'component_product_id': 'p-profile',
      'component_code': 'PROFILE-40',
      'component_name': 'Profile',
      'component_unit': 'm',
      'component_type': 'purchased',
      'component_tracking': 'none',
      'component_has_bom': false,
      'quantity': '6.5',
      'scrap_percent': '10',
      'notes': '',
    },
  ],
};

Map<String, Object?> _routingOp(
  String id,
  int position,
  String name, {
  String centre = 'wc1',
  String code = 'SAW',
  int setup = 30,
  String run = '10',
}) => {
  'id': id,
  'position': position,
  'name': name,
  'work_centre_id': centre,
  'work_centre_code': code,
  'work_centre_name': code,
  'setup_minutes': setup,
  'run_minutes_per_unit': run,
  'notes': '',
};

Map<String, Object?> _workCentre(String id, String code, {bool active = true}) => {
  'id': id,
  'code': code,
  'name': code,
  'division_id': null,
  'division_name': null,
  'capacity': 1,
  'cost_per_hour': null,
  'active': active,
  'sort_order': 0,
  'notes': '',
  'open_operations': 0,
  'hours': <Object?>[],
};

FakeHttp _http({
  required List<String> perms,
  required String status,
  List<Map<String, Object?>> ops = const [],
  Map<String, Object? Function(Object?)> extra = const {},
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/products/p-unit/boms': (_) => [
    {
      'id': 'b2',
      'product_id': 'p-unit',
      'revision': 2,
      'status': status,
      'line_count': 1,
      'notes': '',
      'created_at': '2099-01-01T10:00:00Z',
      'activated_at': status == 'draft' ? null : '2099-01-02T10:00:00Z',
    },
  ],
  'GET /api/v1/boms/b2': (_) => _bom(status),
  'GET /api/v1/boms/b2/routing': (_) => {
    'bom_id': 'b2',
    'product_id': 'p-unit',
    'bom_revision': 2,
    'bom_status': status,
    'operations': ops,
  },
  'PUT /api/v1/boms/b2': (_) => _bom(status),
  'PUT /api/v1/boms/b2/routing': (_) => {
    'bom_id': 'b2',
    'product_id': 'p-unit',
    'bom_revision': 2,
    'bom_status': status,
    'operations': ops,
  },
  'GET /api/v1/production/work-centres': (_) => [
    _workCentre('wc1', 'SAW'),
    _workCentre('wc2', 'WELD'),
    _workCentre('wc3', 'OLD', active: false),
  ],
  'GET /api/v1/products/p-unit/bom/explode': (_) => {
    'product_id': 'p-unit',
    'bom_revision': 2,
    'quantity': '1',
    'nodes': <Object?>[],
    'requirements': <Object?>[],
  },
  ...extra,
});

Future<void> _pump(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1500, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: BomTab(product: _product)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _editor = ['bom.read', 'bom.write', 'production.read'];

void main() {
  testWidgets('a draft shows its routing for editing', (tester) async {
    final http = _http(
      perms: _editor,
      status: 'draft',
      ops: [
        _routingOp('r1', 1, 'Cut'),
        _routingOp('r2', 2, 'Weld', centre: 'wc2', code: 'WELD', setup: 0, run: '6.25'),
      ],
    );
    await _pump(tester, http);
    expect(find.text('Routing'), findsOneWidget);
    expect(
      (tester.widget(find.byKey(const ValueKey('op-name-0'))) as TextField)
          .controller!
          .text,
      'Cut',
    );
    expect(
      (tester.widget(find.byKey(const ValueKey('op-setup-0'))) as TextField)
          .controller!
          .text,
      '30',
    );
    expect(
      (tester.widget(find.byKey(const ValueKey('op-run-1'))) as TextField)
          .controller!
          .text,
      '6,25',
    );
    expect(find.byKey(const ValueKey('add-operation')), findsOneWidget);
  });

  testWidgets('an active revision shows the routing read-only', (tester) async {
    final http = _http(
      perms: _editor,
      status: 'active',
      ops: [_routingOp('r1', 1, 'Cut')],
    );
    await _pump(tester, http);
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('SAW · SAW'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-operation')), findsNothing);
    expect(find.byKey(const ValueKey('op-name-0')), findsNothing);
  });

  testWidgets('an active revision without a routing says so', (tester) async {
    await _pump(tester, _http(perms: _editor, status: 'active'));
    expect(find.textContaining('No routing'), findsOneWidget);
  });

  testWidgets('someone who does not see production has no routing', (tester) async {
    final http = _http(
      perms: ['bom.read', 'bom.write'],
      status: 'draft',
      ops: [_routingOp('r1', 1, 'Cut')],
    );
    await _pump(tester, http);
    expect(find.text('Routing'), findsNothing);
    expect(http.requests, isNot(contains('GET /api/v1/boms/b2/routing')));
  });

  testWidgets('saving the draft saves the changed routing first', (tester) async {
    final http = _http(
      perms: _editor,
      status: 'draft',
      ops: [_routingOp('r1', 1, 'Cut')],
    );
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('add-operation')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('op-name-1')), 'Weld');
    await tester.enterText(find.byKey(const ValueKey('op-setup-1')), '15');
    await tester.enterText(find.byKey(const ValueKey('op-run-1')), '2,5');
    await tester.tap(find.byKey(const ValueKey('op-centre-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WELD · WELD').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    final routing = http.requests.indexOf('PUT /api/v1/boms/b2/routing');
    final lines = http.requests.indexOf('PUT /api/v1/boms/b2');
    expect(routing, isNonNegative);
    expect(routing, lessThan(lines), reason: 'the routing goes first');
    final sent = http.bodies['PUT /api/v1/boms/b2/routing']! as Map;
    final operations = sent['operations'] as List;
    expect(operations, hasLength(2));
    expect(operations[0]['name'], 'Cut');
    expect(operations[0]['work_centre_id'], 'wc1');
    expect(operations[1], {
      'name': 'Weld',
      'work_centre_id': 'wc2',
      'setup_minutes': 15,
      'run_minutes_per_unit': '2.5',
      'notes': '',
    });
  });

  testWidgets('an unchanged routing is not sent again', (tester) async {
    final http = _http(
      perms: _editor,
      status: 'draft',
      ops: [_routingOp('r1', 1, 'Cut')],
    );
    await _pump(tester, http);
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('PUT /api/v1/boms/b2'));
    expect(http.requests, isNot(contains('PUT /api/v1/boms/b2/routing')));
  });

  testWidgets('operations can be reordered and removed', (tester) async {
    final http = _http(
      perms: _editor,
      status: 'draft',
      ops: [_routingOp('r1', 1, 'Cut'), _routingOp('r2', 2, 'Weld')],
    );
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('op-down-0')));
    await tester.pumpAndSettle();
    expect(
      (tester.widget(find.byKey(const ValueKey('op-name-0'))) as TextField)
          .controller!
          .text,
      'Weld',
    );
    await tester.tap(find.byKey(const ValueKey('op-remove-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('op-name-1')), findsNothing);
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    final sent = http.bodies['PUT /api/v1/boms/b2/routing']! as Map;
    expect((sent['operations'] as List).map((o) => o['name']), ['Cut']);
  });

  testWidgets('an operation needs a name before the routing is saved', (tester) async {
    final http = _http(perms: _editor, status: 'draft');
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('add-operation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(http.requests, isNot(contains('PUT /api/v1/boms/b2/routing')));
    expect(http.requests, isNot(contains('PUT /api/v1/boms/b2')));
  });

  testWidgets('only active work centres can be chosen', (tester) async {
    final http = _http(
      perms: _editor,
      status: 'draft',
      ops: [_routingOp('r1', 1, 'Cut')],
    );
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('op-centre-0')));
    await tester.pumpAndSettle();
    expect(find.text('WELD · WELD'), findsWidgets);
    expect(find.text('OLD · OLD'), findsNothing);
  });

  testWidgets('without work centres the routing cannot grow yet', (tester) async {
    final http = _http(
      perms: _editor,
      status: 'draft',
      extra: {'GET /api/v1/production/work-centres': (_) => <Object?>[]},
    );
    await _pump(tester, http);
    expect(
      tester.widget<OutlinedButton>(find.byKey(const ValueKey('add-operation'))).onPressed,
      isNull,
    );
    expect(find.textContaining('Add work centres first'), findsOneWidget);
  });

  testWidgets('the cost roll-up is for those who see cost', (tester) async {
    final rollup = {
      'product_id': 'p-unit',
      'product_code': 'FRAME-A',
      'product_name': 'Frame assembly',
      'unit': 'pcs',
      'quantity': '2',
      'currency': 'EUR',
      'material_cost': '167.48',
      'labour_cost': '145',
      'total_cost': '312.48',
      'unit_cost': '156.24',
      'levels': [
        {
          'level': 0,
          'product_id': 'p-unit',
          'product_code': 'FRAME-A',
          'product_name': 'Frame assembly',
          'unit': 'pcs',
          'quantity': '2',
          'material_cost': '167.48',
          'labour_cost': '145',
          'minutes': 170,
        },
      ],
      'gaps': [
        {'kind': 'standard_cost', 'code': 'CTRL-01'},
        {'kind': 'cost_per_hour', 'code': 'ASM'},
      ],
    };
    final http = _http(
      perms: [..._editor, 'inventory.cost'],
      status: 'active',
      extra: {
        'GET /api/v1/production/products/p-unit/cost-rollup': (_) => rollup,
      },
    );
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('cost-rollup')));
    await tester.pumpAndSettle();
    expect(find.text('Cost roll-up · FRAME-A'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('rollup-total')),
        matching: find.text('€ 312,48'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('rollup-unit')),
        matching: find.text('€ 156,24'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gap-standard_cost-CTRL-01')), findsOneWidget);
    expect(find.text('No cost per hour: ASM'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('rollup-quantity')), '5');
    await tester.tap(find.byKey(const ValueKey('rollup-calculate')));
    await tester.pumpAndSettle();
    expect(http.queries.last['quantity'], '5');
  });

  testWidgets('without the cost right there is no roll-up', (tester) async {
    await _pump(tester, _http(perms: _editor, status: 'active'));
    expect(find.byKey(const ValueKey('cost-rollup')), findsNothing);
  });
}
