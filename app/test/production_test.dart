import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/production/capacity_page.dart';
import 'package:tradocraft_app/features/production/divisions_page.dart';
import 'package:tradocraft_app/features/production/order_production.dart';
import 'package:tradocraft_app/features/production/production_page.dart';
import 'package:tradocraft_app/features/production/production_screen.dart';
import 'package:tradocraft_app/features/production/release_page.dart';
import 'package:tradocraft_app/features/production/work_centres_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _component({
  String id = 'c1',
  String code = 'PROFILE-40',
  String tracking = 'none',
  String required = '14.3',
  String reserved = '14.3',
  bool manufactured = false,
  bool short = false,
}) => {
  'id': id,
  'position': 1,
  'component_product_id': 'p-$id',
  'component_code': code,
  'component_name': 'Steel profile',
  'unit': 'm',
  'tracking': tracking,
  'required_quantity': required,
  'reserved_quantity': reserved,
  'consumed_quantity': '0',
  'scrap_quantity': '0',
  'manufactured': manufactured,
  'short': short,
};

Map<String, Object?> _operation({
  String id = 'op1',
  int position = 1,
  String name = 'Cut',
  String status = 'pending',
  int planned = 50,
  int? actual,
  String start = '2099-03-01',
  String end = '2099-03-01',
}) => {
  'id': id,
  'position': position,
  'name': name,
  'work_centre_id': 'wc1',
  'work_centre_code': 'SAW',
  'work_centre_name': 'Saw',
  'setup_minutes': 30,
  'run_minutes_per_unit': '10',
  'planned_minutes': planned,
  'planned_start': start,
  'planned_end': end,
  'status': status,
  'started_at': null,
  'completed_at': null,
  'completed_by': null,
  'completed_by_name': null,
  'actual_minutes': actual,
  'cost_rate': null,
  'notes': '',
};

Map<String, Object?> _summary({
  String id = 'po1',
  String status = 'released',
  int short = 0,
  bool orderCancelled = false,
  String tracking = 'none',
  int operations = 0,
  int operationsDone = 0,
  bool behind = false,
}) => {
  'id': id,
  'number': 'MO2099-00001',
  'product_id': 'p1',
  'product_code': 'FRAME-A',
  'product_name': 'Frame assembly',
  'unit': 'pcs',
  'product_tracking': tracking,
  'quantity': '2',
  'bom_revision': 1,
  'division_id': 'd1',
  'division_name': 'Welding',
  'order_id': 'o1',
  'order_number': 'SO2099-00001',
  'customer_name': 'Alpha Installaties NV',
  'priority': 'expedite',
  'order_cancelled': orderCancelled,
  'status': status,
  'planned_ready_date': '2099-07-01',
  'short_components': short,
  'operation_count': operations,
  'operations_done': operationsDone,
  'behind_schedule': behind,
  'created_at': '2099-01-01T10:00:00Z',
};

Map<String, Object?> _order({
  String status = 'released',
  List<Map<String, Object?>>? components,
  bool orderCancelled = false,
  String tracking = 'none',
  List<Map<String, Object?>> operations = const [],
  List<Map<String, Object?>> subOrders = const [],
  String? remark,
  String? scheduledEnd,
  bool behind = false,
  Map<String, Object?>? plannedCost,
  Map<String, Object?>? actualCost,
}) => {
  ..._summary(
    status: status,
    orderCancelled: orderCancelled,
    tracking: tracking,
    short: (components ?? [_component()])
        .where((c) => c['short'] == true)
        .length,
    operations: operations.length,
    operationsDone: operations.where((o) => o['status'] == 'done').length,
    behind: behind,
  ),
  'operations': operations,
  'sub_orders': subOrders,
  'parent_order_number': null,
  'production_remark': remark,
  'scheduled_end': scheduledEnd,
  'planned_cost': plannedCost,
  'actual_cost': actualCost,
  'order_line_id': 'ol1',
  'parent_order_id': null,
  'started_at': null,
  'completed_at': null,
  'completed_quantity': null,
  'notes': '',
  'cancel_reason': null,
  'components': components ?? [_component()],
  'outputs': <Object?>[],
};

Map<String, Object?> _division({
  String id = 'd1',
  String code = 'WELD',
  String name = 'Welding',
  bool isMember = false,
  List<Map<String, Object?>> members = const [],
}) => {
  'id': id,
  'code': code,
  'name': name,
  'sort_order': 1,
  'active': true,
  'open_orders': 2,
  'members': members,
  'is_member': isMember,
};

Map<String, Object?> _companyUser(String id, String name) => {
  'id': id,
  'display_name': name,
  'email': '$id@example.com',
  'roles': ['workshop'],
};

Map<String, Object?> _warehouse() => {
  'id': 'w1',
  'code': 'WH1',
  'name': 'Main warehouse',
  'kind': 'warehouse',
  'active': true,
  'assigned_user_id': null,
  'assigned_user_name': null,
  'locations': [
    {
      'id': 'l1',
      'warehouse_id': 'w1',
      'code': 'MAIN',
      'name': '',
      'active': true,
    },
  ],
};

Map<String, Object?> _toRelease() => {
  'order_id': 'o1',
  'order_number': 'SO2099-00001',
  'customer_name': 'Alpha Installaties NV',
  'priority': 'normal',
  'order_line_id': 'ol1',
  'product_id': 'p1',
  'product_code': 'FRAME-A',
  'product_name': 'Frame assembly',
  'ordered': '2',
  'planned': '0',
  'to_build': '2',
};

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http,
  Widget home, {
  KvStore? store,
}) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: '/production/:id',
        builder: (_, s) =>
            Scaffold(body: Text('production ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/production/release',
        builder: (_, _) => const Scaffold(body: Text('release page')),
      ),
      GoRoute(
        path: '/production/divisions',
        builder: (_, _) => const Scaffold(body: Text('divisions page')),
      ),
      GoRoute(
        path: '/production/work-centres',
        builder: (_, _) => const Scaffold(body: Text('work centres page')),
      ),
      GoRoute(
        path: '/production/capacity',
        builder: (_, _) => const Scaffold(body: Text('capacity page')),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, s) =>
            Scaffold(body: Text('order ${s.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(store ?? MemoryKvStore()),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _planner = ['production.read', 'production.write', 'production.run'];

FakeHttp _screenHttp(
  List<String> perms, {
  Map<String, Object?>? order,
  Map<String, Object? Function(Object?)> extra = const {},
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/production-orders/po1': (_) => order ?? _order(),
  'GET /api/v1/production/divisions': (_) => [_division()],
  'GET /api/v1/inventory/warehouses': (_) => [_warehouse()],
  ...extra,
});

/// A queue server: [divisions], the caller's [perms], and the orders it returns per `mine` flag.
FakeHttp _queueHttp(List<String> perms, List<Map<String, Object?>> divisions) =>
    FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/production/divisions': (_) => divisions,
      'GET /api/v1/production-orders': (_) => {
        'items': [_summary()],
        'total': 1,
      },
    });

void main() {
  testWidgets('the queue shows the urgent orders and flags what is short', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) =>
          meJson(['production.read', 'production.admin', 'production.write']),
      'GET /api/v1/production/divisions': (_) => [_division()],
      'GET /api/v1/production-orders': (_) => {
        'items': [_summary(short: 1)],
        'total': 1,
      },
    });
    await _pump(tester, http, const ProductionQueuePage());
    expect(find.text('MO2099-00001'), findsWidgets);
    expect(find.textContaining('FRAME-A'), findsWidgets);
    expect(find.byTooltip('short of stock'), findsOneWidget);
    expect(find.byKey(const ValueKey('to-release')), findsOneWidget);
    expect(find.byKey(const ValueKey('divisions')), findsOneWidget);
    expect(find.text('Build for stock'), findsOneWidget);
  });

  testWidgets('a reader sees the queue without planning or admin buttons', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['production.read']),
      'GET /api/v1/production/divisions': (_) => [_division()],
      'GET /api/v1/production-orders': (_) => {
        'items': <Object?>[],
        'total': 0,
      },
    });
    await _pump(tester, http, const ProductionQueuePage());
    expect(find.byKey(const ValueKey('divisions')), findsNothing);
    expect(find.text('Build for stock'), findsNothing);
  });

  testWidgets('the planner releases a line from the to-release list', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(_planner),
      'GET /api/v1/production/to-release': (_) => [_toRelease()],
      'POST /api/v1/production-orders': (_) => _order(),
    });
    await _pump(tester, http, const ReleasePage());
    expect(find.textContaining('FRAME-A'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('release-button-ol1')));
    await tester.pumpAndSettle();
    final sent = http.bodies['POST /api/v1/production-orders']! as Map;
    expect(sent['order_id'], 'o1');
    expect(sent['order_line_id'], 'ol1');
    expect(
      find.text('production po1'),
      findsOneWidget,
      reason: 'opens the new order',
    );
  });

  testWidgets('with nothing to release the list says so', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(_planner),
      'GET /api/v1/production/to-release': (_) => <Object?>[],
    });
    await _pump(tester, http, const ReleasePage());
    expect(find.textContaining('Nothing to release'), findsOneWidget);
  });

  testWidgets(
    'the order screen saves division, date and notes and starts the order',
    (tester) async {
      final http = _screenHttp(
        _planner,
        extra: {
          'PUT /api/v1/production-orders/po1': (_) => _order(),
          'POST /api/v1/production-orders/po1/start': (_) =>
              _order(status: 'in_progress'),
        },
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      expect(find.textContaining('PROFILE-40'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save-production')));
      await tester.pumpAndSettle();
      final sent = http.bodies['PUT /api/v1/production-orders/po1']! as Map;
      expect(sent['division_id'], 'd1');
      expect(
        (sent['planned_ready_date'] as String).startsWith('2099-07-01'),
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('start-production')));
      await tester.pumpAndSettle();
      expect(
        http.requests,
        contains('POST /api/v1/production-orders/po1/start'),
      );
      expect(find.byKey(const ValueKey('start-production')), findsNothing);
    },
  );

  testWidgets(
    'a short manufactured component can be built and reserved again',
    (tester) async {
      final short = _component(
        id: 'c9',
        code: 'SUB-1',
        required: '3',
        reserved: '1',
        manufactured: true,
        short: true,
      );
      final http = _screenHttp(
        _planner,
        order: _order(components: [short]),
        extra: {
          'POST /api/v1/production-orders/po1/components/c9/build': (_) => {
            ..._order(),
            'id': 'child',
          },
          // Still short after trying again: nothing arrived in stock.
          'POST /api/v1/production-orders/po1/reserve': (_) =>
              _order(components: [short]),
        },
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      expect(find.text('short of stock'), findsNothing);
      expect(find.textContaining('short of stock'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('reserve-again')));
      await tester.pumpAndSettle();
      expect(
        http.requests,
        contains('POST /api/v1/production-orders/po1/reserve'),
      );

      await tester.tap(find.byKey(const ValueKey('build-c9')));
      await tester.pumpAndSettle();
      // The server works out how much is missing; the app sends no quantity.
      expect(
        http.requests,
        contains('POST /api/v1/production-orders/po1/components/c9/build'),
      );
      expect(http.requests, isNot(contains('POST /api/v1/production-orders')));
      expect(find.text('production child'), findsOneWidget);
    },
  );

  testWidgets('cancelling asks for a reason', (tester) async {
    final http = _screenHttp(
      _planner,
      extra: {
        'POST /api/v1/production-orders/po1/cancel': (_) =>
            _order(status: 'cancelled'),
      },
    );
    await _pump(tester, http, const ProductionScreen(id: 'po1'));
    await tester.tap(find.byKey(const ValueKey('cancel-production')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'customer changed it');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final sent =
        http.bodies['POST /api/v1/production-orders/po1/cancel']! as Map;
    expect(sent['reason'], 'customer changed it');
    expect(find.byKey(const ValueKey('cancel-production')), findsNothing);
  });

  testWidgets('a cancelled sales order is flagged and cannot be completed', (
    tester,
  ) async {
    final http = _screenHttp(_planner, order: _order(orderCancelled: true));
    await _pump(tester, http, const ProductionScreen(id: 'po1'));
    expect(find.byKey(const ValueKey('order-cancelled')), findsOneWidget);
    expect(find.byKey(const ValueKey('complete-production')), findsNothing);
    expect(find.byKey(const ValueKey('cancel-production')), findsOneWidget);
  });

  testWidgets('a reader sees the order but has no actions', (tester) async {
    final http = _screenHttp(['production.read']);
    await _pump(tester, http, const ProductionScreen(id: 'po1'));
    for (final k in [
      'save-production',
      'start-production',
      'complete-production',
      'cancel-production',
    ]) {
      expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
    }
    expect(find.textContaining('PROFILE-40'), findsOneWidget);
  });

  testWidgets('completing sends the output and the actual consumption', (
    tester,
  ) async {
    final http = _screenHttp(
      _planner,
      extra: {
        'POST /api/v1/production-orders/po1/complete': (_) =>
            _order(status: 'completed'),
      },
    );
    await _pump(tester, http, const ProductionScreen(id: 'po1'));
    await tester.tap(find.byKey(const ValueKey('complete-production')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('output-quantity')), '2');
    // The location is a dropdown of the stock locations.
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WH1/MAIN').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('scrap-c1')), '1');
    await tester.pumpAndSettle();
    // 14.3 used + 1 scrapped is more than the 14.3 reserved: the rest needs a place.
    expect(find.byKey(const ValueKey('extra-c1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('complete-save')));
    await tester.pumpAndSettle();
    final sent =
        http.bodies['POST /api/v1/production-orders/po1/complete']! as Map;
    expect(sent['output']['quantity'], '2');
    expect(sent['output']['location_id'], 'l1');
    final c = (sent['components'] as List).first as Map;
    expect(c['component_id'], 'c1');
    expect(c['consumed_quantity'], '14.3');
    expect(c['scrap_quantity'], '1');
    expect(
      find.byKey(const ValueKey('complete-save')),
      findsNothing,
      reason: 'closed',
    );
    expect(find.text('Production order completed'), findsOneWidget);
  });

  testWidgets('a refused completion keeps the dialog open with the reason', (
    tester,
  ) async {
    final http = _screenHttp(
      _planner,
      extra: {
        'POST /api/v1/production-orders/po1/complete': (_) => const FakeStatus(
          422,
          {'error': 'validation', 'message': 'a lot number is needed'},
        ),
      },
    );
    await _pump(tester, http, const ProductionScreen(id: 'po1'));
    await tester.tap(find.byKey(const ValueKey('complete-production')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WH1/MAIN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('a lot number is needed'), findsOneWidget);
    expect(find.byKey(const ValueKey('complete-save')), findsOneWidget);
  });

  testWidgets(
    'lot and serial output ask for their numbers, serial components for their units',
    (tester) async {
      final serial = _component(
        id: 'c2',
        code: 'PUMP-05',
        tracking: 'serial',
        required: '2',
        reserved: '2',
      );
      final http = _screenHttp(
        _planner,
        order: _order(components: [serial], tracking: 'serial'),
        extra: {
          'GET /api/v1/production-orders/po1/components/c2/serial-units': (_) =>
              [
                {
                  'id': 'u1',
                  'serial_number': 'P-1',
                  'location_id': 'l1',
                  'location': 'WH1/MAIN',
                },
                {
                  'id': 'u2',
                  'serial_number': 'P-2',
                  'location_id': 'l1',
                  'location': 'WH1/MAIN',
                },
              ],
          'POST /api/v1/production-orders/po1/complete': (_) =>
              _order(status: 'completed'),
        },
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      await tester.tap(find.byKey(const ValueKey('complete-production')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('output-serials')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('scrap-c2')),
        findsNothing,
        reason: 'units are scrapped separately',
      );
      await tester.enterText(
        find.byKey(const ValueKey('output-quantity')),
        '1',
      );
      await tester.enterText(find.byKey(const ValueKey('consumed-c2')), '2');
      await tester.enterText(
        find.byKey(const ValueKey('output-serials')),
        'U-1\n',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('WH1/MAIN').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('units-c2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('unit-u1')));
      await tester.tap(find.byKey(const ValueKey('unit-u2')));
      await tester.tap(find.byKey(const ValueKey('units-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('P-1, P-2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('complete-save')));
      await tester.pumpAndSettle();
      final sent =
          http.bodies['POST /api/v1/production-orders/po1/complete']! as Map;
      expect(sent['output']['serial_numbers'], ['U-1']);
      final c = (sent['components'] as List).first as Map;
      expect(c['serial_unit_ids'], ['u1', 'u2']);
      expect(c.containsKey('scrap_quantity'), isFalse);
    },
  );

  testWidgets('a lot-tracked output asks for its lot', (tester) async {
    final http = _screenHttp(
      _planner,
      order: _order(tracking: 'lot'),
      extra: {
        'POST /api/v1/production-orders/po1/complete': (_) =>
            _order(status: 'completed'),
      },
    );
    await _pump(tester, http, const ProductionScreen(id: 'po1'));
    await tester.tap(find.byKey(const ValueKey('complete-production')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('output-lot')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('output-lot')), 'F-001');
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WH1/MAIN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-save')));
    await tester.pumpAndSettle();
    final sent =
        http.bodies['POST /api/v1/production-orders/po1/complete']! as Map;
    expect(sent['output']['lot_number'], 'F-001');
  });

  testWidgets(
    'the order lists its production orders and releases what is left',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_planner),
        'GET /api/v1/production-orders': (_) => {
          'items': [_summary(short: 1)],
          'total': 1,
        },
        'GET /api/v1/production/to-release': (_) => [_toRelease()],
        'POST /api/v1/production-orders': (_) => _order(),
      });
      var changed = 0;
      await _pump(
        tester,
        http,
        OrderProduction(
          orderId: 'o1',
          orderStatus: 'confirmed',
          onChanged: () => changed++,
        ),
      );
      final list = http.requests.indexOf('GET /api/v1/production-orders');
      expect(http.queries[list]['order_id'], 'o1');
      expect(find.textContaining('MO2099-00001'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('release-order')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('POST /api/v1/production-orders'));
      expect(
        changed,
        1,
        reason: 'the order refreshes: its status follows production',
      );
    },
  );

  testWidgets(
    'releasing with nothing left says so, and a reader cannot release',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_planner),
        'GET /api/v1/production-orders': (_) => {
          'items': <Object?>[],
          'total': 0,
        },
        'GET /api/v1/production/to-release': (_) => <Object?>[],
      });
      await _pump(
        tester,
        http,
        const OrderProduction(orderId: 'o1', orderStatus: 'confirmed'),
      );
      await tester.tap(find.byKey(const ValueKey('release-order')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing to release'), findsOneWidget);
      expect(http.requests, isNot(contains('POST /api/v1/production-orders')));

      final reader = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['production.read']),
        'GET /api/v1/production-orders': (_) => {
          'items': <Object?>[],
          'total': 0,
        },
      });
      await _pump(
        tester,
        reader,
        const OrderProduction(orderId: 'o1', orderStatus: 'confirmed'),
      );
      expect(find.byKey(const ValueKey('release-order')), findsNothing);
    },
  );

  testWidgets(
    'the administrator adds and removes divisions; others are told they cannot',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) =>
            meJson(['production.read', 'production.admin']),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'POST /api/v1/production/divisions': (_) =>
            _division(id: 'd2', code: 'ASM'),
        'DELETE /api/v1/production/divisions/d1': (_) => null,
      });
      await _pump(tester, http, const DivisionsPage());
      expect(find.textContaining('WELD'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-division')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('division-code')),
        'ASM',
      );
      await tester.enterText(
        find.byKey(const ValueKey('division-name')),
        'Assembly',
      );
      await tester.tap(find.byKey(const ValueKey('division-save')));
      await tester.pumpAndSettle();
      final sent = http.bodies['POST /api/v1/production/divisions']! as Map;
      expect(sent['code'], 'ASM');
      expect(sent['name'], 'Assembly');
      await tester.tap(find.byKey(const ValueKey('delete-d1')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/production/divisions/d1'));

      final reader = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['production.read']),
        'GET /api/v1/production/divisions': (_) => [_division()],
      });
      await _pump(tester, reader, const DivisionsPage());
      expect(find.byKey(const ValueKey('add-division')), findsNothing);
      expect(find.textContaining('permission'), findsOneWidget);
    },
  );

  testWidgets('an exact fit in decimals never asks for an extra place', (
    tester,
  ) async {
    // 0.1 + 0.2 is more than 0.3 in binary floating point, but exactly 0.3 in decimals.
    final http = _screenHttp(
      _planner,
      order: _order(
        components: [_component(required: '0.3', reserved: '0.3')],
      ),
    );
    await _pump(tester, http, const ProductionScreen(id: 'po1'));
    await tester.tap(find.byKey(const ValueKey('complete-production')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('consumed-c1')), '0.1');
    await tester.enterText(find.byKey(const ValueKey('scrap-c1')), '0.2');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('extra-c1')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('scrap-c1')), '0.3');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('extra-c1')), findsOneWidget);
  });

  testWidgets('lines released before a failure still refresh the order', (
    tester,
  ) async {
    var posts = 0;
    final second = {..._toRelease(), 'order_line_id': 'ol2'};
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(_planner),
      'GET /api/v1/production-orders': (_) => {
        'items': [_summary()],
        'total': 1,
      },
      'GET /api/v1/production/to-release': (_) => [_toRelease(), second],
      'POST /api/v1/production-orders': (_) => ++posts == 1
          ? _order()
          : const FakeStatus(409, {
              'error': 'conflict',
              'message': 'no active BOM',
            }),
    });
    var changed = 0;
    await _pump(
      tester,
      http,
      OrderProduction(
        orderId: 'o1',
        orderStatus: 'confirmed',
        onChanged: () => changed++,
      ),
    );
    final loads = http.requests
        .where((r) => r == 'GET /api/v1/production-orders')
        .length;
    await tester.tap(find.byKey(const ValueKey('release-order')));
    await tester.pumpAndSettle();
    expect(posts, 2);
    expect(find.textContaining('no active BOM'), findsOneWidget);
    expect(changed, 1, reason: 'the first line was released');
    expect(
      http.requests.where((r) => r == 'GET /api/v1/production-orders').length,
      loads + 1,
      reason: 'the list is reloaded',
    );
  });

  testWidgets('an order keeps showing its division after it was deactivated', (
    tester,
  ) async {
    final http = _screenHttp(
      _planner,
      extra: {
        'GET /api/v1/production/divisions': (_) => [
          {..._division(), 'active': false},
        ],
      },
    );
    await _pump(tester, http, const ProductionScreen(id: 'po1'));
    expect(
      find.text('Welding'),
      findsOneWidget,
      reason: 'not replaced by "no division"',
    );
  });

  group('division scope of the queue', () {
    final mineDivision = _division(isMember: true, name: 'Electronics');
    final otherDivision = _division(id: 'd2', code: 'MECH', name: 'Mechanics');
    bool lastMine(FakeHttp http) => http.queries.last['mine'] == true;
    bool anyMine(FakeHttp http) => http.queries.any((q) => q['mine'] == true);
    const worker = ['production.read', 'production.run'];

    testWidgets('a worker with divisions starts on their own divisions', (
      tester,
    ) async {
      final http = _queueHttp(worker, [mineDivision, otherDivision]);
      await _pump(tester, http, const ProductionQueuePage());
      expect(find.byKey(const ValueKey('queue-scope')), findsOneWidget);
      expect(find.text('My divisions'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-divisions')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('my-divisions')),
          matching: find.text('Electronics'),
        ),
        findsOneWidget,
      );
      expect(http.queries.where((q) => q.containsKey('mine')), isNotEmpty);
      expect(lastMine(http), isTrue);
    });

    testWidgets('planners and admins start on all divisions', (tester) async {
      for (final perms in [
        _planner,
        ['production.read', 'production.admin'],
      ]) {
        final http = _queueHttp(perms, [mineDivision, otherDivision]);
        await _pump(tester, http, const ProductionQueuePage());
        expect(find.byKey(const ValueKey('queue-scope')), findsOneWidget);
        expect(anyMine(http), isFalse, reason: '$perms');
      }
    });

    testWidgets('without a division the control is hidden', (tester) async {
      final http = _queueHttp(worker, [otherDivision]);
      await _pump(tester, http, const ProductionQueuePage());
      expect(find.byKey(const ValueKey('queue-scope')), findsNothing);
      expect(find.byKey(const ValueKey('my-divisions')), findsNothing);
      expect(anyMine(http), isFalse);
    });

    testWidgets('the toggle changes the request and is remembered', (
      tester,
    ) async {
      final store = MemoryKvStore();
      final http = _queueHttp(worker, [mineDivision]);
      await _pump(tester, http, const ProductionQueuePage(), store: store);
      expect(lastMine(http), isTrue);
      await tester.tap(find.text('All divisions'));
      await tester.pumpAndSettle();
      expect(http.queries.last['mine'], isNot(true));
      // A new queue page for the same user opens on the remembered choice.
      final again = _queueHttp(worker, [mineDivision]);
      await _pump(tester, again, const ProductionQueuePage(), store: store);
      expect(anyMine(again), isFalse);
      await tester.tap(find.text('My divisions'));
      await tester.pumpAndSettle();
      expect(lastMine(again), isTrue);
    });

    testWidgets('an empty view explains and offers to show all', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(worker),
        'GET /api/v1/production/divisions': (_) => [mineDivision],
        'GET /api/v1/production-orders': (_) => {
          'items': <Object?>[],
          'total': 0,
        },
      });
      await _pump(tester, http, const ProductionQueuePage());
      expect(
        find.text(
          'No orders in your divisions. Orders without a division are included.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('scope-show-all')));
      await tester.pumpAndSettle();
      expect(http.queries.last['mine'], isNot(true));
      expect(find.byKey(const ValueKey('scope-show-all')), findsNothing);
    });
  });

  testWidgets('the administrator picks the members of a division', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['production.read', 'production.admin']),
      'GET /api/v1/users': (_) => [
        _companyUser('u1', 'Els Electronics'),
        _companyUser('u2', 'Max Mechanic'),
      ],
      'GET /api/v1/production/divisions': (_) => [
        _division(
          members: [
            {'user_id': 'u1', 'display_name': 'Els Electronics'},
          ],
        ),
      ],
      'POST /api/v1/production/divisions': (_) => _division(id: 'd2'),
      'PUT /api/v1/production/divisions/d1': (_) => _division(),
    });
    await _pump(tester, http, const DivisionsPage());
    // The list shows the members.
    expect(find.textContaining('Els Electronics'), findsOneWidget);
    // Editing starts from the current members; the selection replaces them.
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-u1')));
    await tester.tap(find.byKey(const ValueKey('member-u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('division-save')));
    await tester.pumpAndSettle();
    final put = http.bodies['PUT /api/v1/production/divisions/d1']! as Map;
    expect(put['member_user_ids'], ['u2']);
    // A new division with two members.
    await tester.tap(find.byKey(const ValueKey('add-division')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('division-code')), 'MECH');
    await tester.enterText(
      find.byKey(const ValueKey('division-name')),
      'Mechanics',
    );
    await tester.tap(find.byKey(const ValueKey('member-u1')));
    await tester.tap(find.byKey(const ValueKey('member-u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('division-save')));
    await tester.pumpAndSettle();
    final post = http.bodies['POST /api/v1/production/divisions']! as Map;
    expect(post['member_user_ids'], unorderedEquals(['u1', 'u2']));
  });

  group('work centres, routings and operations', () {
    Map<String, Object?> workCentre({
      String id = 'wc1',
      String code = 'SAW',
      String name = 'Saw',
      bool active = true,
      String? cost = '30',
      List<Map<String, Object?>> hours = const [],
    }) => {
      'id': id,
      'code': code,
      'name': name,
      'division_id': 'd1',
      'division_name': 'Welding',
      'capacity': 2,
      'cost_per_hour': cost,
      'active': active,
      'sort_order': 0,
      'notes': '',
      'open_operations': 3,
      'hours': hours,
    };

    final ops = [
      _operation(id: 'op1', name: 'Cut'),
      _operation(id: 'op2', position: 2, name: 'Weld', status: 'in_progress'),
      _operation(
        id: 'op3',
        position: 3,
        name: 'Paint',
        status: 'done',
        actual: 40,
      ),
    ];

    FakeHttp opsHttp(
      List<String> perms, {
      Map<String, Object?>? order,
      Map<String, Object? Function(Object?)> extra = const {},
    }) => _screenHttp(
      perms,
      order: order ?? _order(status: 'in_progress', operations: ops),
      extra: {
        'GET /api/v1/production/work-centres': (_) => [
          workCentre(),
          workCentre(id: 'wc2', code: 'WELD', name: 'Welding'),
        ],
        ...extra,
      },
    );

    testWidgets('an order without a routing shows no operations', (
      tester,
    ) async {
      await _pump(
        tester,
        _screenHttp(_planner),
        const ProductionScreen(id: 'po1'),
      );
      expect(find.text('Operations'), findsNothing);
      expect(find.byKey(const ValueKey('schedule-again')), findsNothing);
    });

    testWidgets('operations show where they run, what is planned and worked', (
      tester,
    ) async {
      await _pump(
        tester,
        opsHttp(_planner),
        const ProductionScreen(id: 'po1'),
      );
      expect(find.text('Operations'), findsOneWidget);
      final cut = find.byKey(const ValueKey('operation-op1'));
      expect(
        find.descendant(of: cut, matching: find.text('1. Cut')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cut,
          matching: find.textContaining('SAW · Planned 50 min · 01/03/2099'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('operation-op3')),
          matching: find.textContaining('Done · Worked 40 min'),
        ),
        findsOneWidget,
      );
      // What can be done depends on where the operation stands.
      expect(find.byKey(const ValueKey('start-op-op1')), findsOneWidget);
      expect(find.byKey(const ValueKey('start-op-op2')), findsNothing);
      expect(find.byKey(const ValueKey('finish-op-op2')), findsOneWidget);
      expect(find.byKey(const ValueKey('reopen-op-op3')), findsOneWidget);
      expect(find.byKey(const ValueKey('finish-op-op3')), findsNothing);
    });

    testWidgets('a reader sees the operations but cannot work on them', (
      tester,
    ) async {
      await _pump(
        tester,
        opsHttp(['production.read']),
        const ProductionScreen(id: 'po1'),
      );
      expect(find.byKey(const ValueKey('operation-op1')), findsOneWidget);
      for (final k in [
        'start-op-op1',
        'finish-op-op2',
        'reopen-op-op3',
        'move-op-op1',
        'schedule-again',
      ]) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
    });

    testWidgets('the floor starts, finishes with minutes, and reopens', (
      tester,
    ) async {
      final http = opsHttp(
        ['production.read', 'production.run'],
        extra: {
          'POST /api/v1/production-orders/po1/operations/op1/start': (_) =>
              _order(
                status: 'in_progress',
                operations: [
                  _operation(id: 'op1', name: 'Cut', status: 'in_progress'),
                ],
              ),
          'POST /api/v1/production-orders/po1/operations/op2/finish': (_) =>
              _order(status: 'in_progress', operations: ops),
          'POST /api/v1/production-orders/po1/operations/op3/reopen': (_) =>
              _order(status: 'in_progress', operations: ops),
        },
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      await tester.tap(find.byKey(const ValueKey('start-op-op1')));
      await tester.pumpAndSettle();
      expect(
        http.requests,
        contains('POST /api/v1/production-orders/po1/operations/op1/start'),
      );
      // The answer replaces the screen: Cut is running now.
      expect(find.byKey(const ValueKey('start-op-op1')), findsNothing);
      expect(find.byKey(const ValueKey('finish-op-op1')), findsOneWidget);
      expect(find.byKey(const ValueKey('operation-op2')), findsNothing);
    });

    testWidgets('finishing asks for the minutes worked', (tester) async {
      final http = opsHttp(
        _planner,
        extra: {
          'POST /api/v1/production-orders/po1/operations/op2/finish': (_) =>
              _order(status: 'in_progress', operations: ops),
          'POST /api/v1/production-orders/po1/operations/op3/reopen': (_) =>
              _order(status: 'in_progress', operations: ops),
        },
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      await tester.tap(find.byKey(const ValueKey('finish-op-op2')));
      await tester.pumpAndSettle();
      // The planned minutes are the starting point.
      final minutes = find.byKey(const ValueKey('finish-minutes'));
      expect(
        (tester.widget(minutes) as TextField).controller!.text,
        '50',
      );
      await tester.enterText(minutes, '95');
      await tester.enterText(
        find.byKey(const ValueKey('finish-note')),
        ' a burr ',
      );
      await tester.tap(find.byKey(const ValueKey('finish-save')));
      await tester.pumpAndSettle();
      final sent =
          http.bodies['POST /api/v1/production-orders/po1/operations/op2/finish']!
              as Map;
      expect(sent['actual_minutes'], 95);
      expect(sent['note'], 'a burr');

      await tester.tap(find.byKey(const ValueKey('reopen-op-op3')));
      await tester.pumpAndSettle();
      expect(
        http.requests,
        contains('POST /api/v1/production-orders/po1/operations/op3/reopen'),
      );
    });

    testWidgets('a planner moves an operation and schedules the rest again', (
      tester,
    ) async {
      final http = opsHttp(
        _planner,
        extra: {
          'PUT /api/v1/production-orders/po1/operations/op1': (_) =>
              _order(status: 'in_progress', operations: ops),
          'POST /api/v1/production-orders/po1/schedule': (_) =>
              _order(status: 'in_progress', operations: ops),
        },
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      await tester.tap(find.byKey(const ValueKey('move-op-op1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('move-centre-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WELD · Welding').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('move-save')));
      await tester.pumpAndSettle();
      final moved =
          http.bodies['PUT /api/v1/production-orders/po1/operations/op1']!
              as Map;
      expect(moved['work_centre_id'], 'wc2');
      expect(moved['planned_start'], startsWith('2099-03-01'));
      expect(moved['planned_end'], startsWith('2099-03-01'));

      await tester.tap(find.byKey(const ValueKey('schedule-again')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        http.requests,
        contains('POST /api/v1/production-orders/po1/schedule'),
      );
      final today = DateTime.now();
      expect(
        (http.bodies['POST /api/v1/production-orders/po1/schedule']!
            as Map)['start_date'],
        startsWith(
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
        ),
      );
    });

    testWidgets(
      'behind schedule is flagged and the scheduled end can be taken over',
      (tester) async {
        final http = opsHttp(
          _planner,
          order: _order(
            operations: [_operation(id: 'op1', end: '2099-08-01')],
            scheduledEnd: '2099-08-01',
            behind: true,
          ),
          extra: {
            'PUT /api/v1/production-orders/po1': (_) =>
                _order(scheduledEnd: '2099-08-01'),
          },
        );
        await _pump(tester, http, const ProductionScreen(id: 'po1'));
        expect(find.byKey(const ValueKey('behind-schedule')), findsOneWidget);
        expect(find.textContaining('01/08/2099'), findsWidgets);
        await tester.tap(find.byKey(const ValueKey('use-scheduled-end')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Planned ready: 01/08/2099'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('save-production')));
        await tester.pumpAndSettle();
        final sent = http.bodies['PUT /api/v1/production-orders/po1']! as Map;
        expect(sent['planned_ready_date'], startsWith('2099-08-01'));
      },
    );

    testWidgets('the order shows the internal remark and, to cost viewers, its cost', (
      tester,
    ) async {
      final cost = {
        'material_cost': '167.48',
        'labour_cost': '145',
        'total_cost': '312.48',
        'incomplete': true,
      };
      await _pump(
        tester,
        opsHttp(
          _planner,
          order: _order(
            remark: 'Paint RAL 5010',
            plannedCost: cost,
            actualCost: {...cost, 'total_cost': '299.98'},
          ),
        ),
        const ProductionScreen(id: 'po1'),
      );
      expect(find.byKey(const ValueKey('production-remark')), findsOneWidget);
      expect(find.text('Paint RAL 5010'), findsOneWidget);
      expect(find.text('€ 312,48'), findsOneWidget);
      expect(find.text('€ 299,98'), findsOneWidget);
      expect(find.text('Some costs are missing and left out.'), findsOneWidget);
    });

    testWidgets('without the cost right there is no cost on the order', (
      tester,
    ) async {
      await _pump(
        tester,
        opsHttp(_planner),
        const ProductionScreen(id: 'po1'),
      );
      expect(find.text('Cost'), findsNothing);
      expect(find.byKey(const ValueKey('production-remark')), findsNothing);
    });

    testWidgets('subassembly orders are listed and open', (tester) async {
      final http = opsHttp(
        _planner,
        order: _order(
          subOrders: [
            {
              'id': 'child1',
              'number': 'MO2099-00002',
              'product_id': 'p9',
              'product_code': 'SUB-1',
              'product_name': 'Sub',
              'unit': 'pcs',
              'quantity': '2',
              'status': 'released',
              'planned_ready_date': null,
              'scheduled_end': '2099-03-02',
            },
          ],
        ),
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      expect(find.text('Subassembly orders'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sub-order-child1')));
      await tester.pumpAndSettle();
      expect(find.text('production child1'), findsOneWidget);
    });

    testWidgets('completing lists the open operations and sends their minutes', (
      tester,
    ) async {
      final http = opsHttp(
        _planner,
        extra: {
          'POST /api/v1/production-orders/po1/complete': (_) =>
              _order(status: 'completed', operations: ops),
        },
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      await tester.tap(find.byKey(const ValueKey('complete-production')));
      await tester.pumpAndSettle();
      // Two operations are open (Cut, Weld); the finished one is not asked about.
      expect(
        find.byKey(const ValueKey('operations-open-warning')),
        findsOneWidget,
      );
      expect(find.textContaining('2 operations are still open'), findsOneWidget);
      expect(find.byKey(const ValueKey('op-minutes-op1')), findsOneWidget);
      expect(find.byKey(const ValueKey('op-minutes-op2')), findsOneWidget);
      expect(find.byKey(const ValueKey('op-minutes-op3')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('op-minutes-op1')), '70');
      // Left empty: the operation is skipped, so it is not sent.
      await tester.enterText(find.byKey(const ValueKey('op-minutes-op2')), '');
      await tester.enterText(find.byKey(const ValueKey('output-quantity')), '2');
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('WH1/MAIN').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('complete-save')));
      await tester.pumpAndSettle();
      final sent =
          http.bodies['POST /api/v1/production-orders/po1/complete']! as Map;
      expect(sent['operations'], [
        {'operation_id': 'op1', 'actual_minutes': 70},
      ]);
    });

    testWidgets('an order without operations completes as before', (
      tester,
    ) async {
      final http = _screenHttp(
        _planner,
        extra: {
          'POST /api/v1/production-orders/po1/complete': (_) =>
              _order(status: 'completed'),
        },
      );
      await _pump(tester, http, const ProductionScreen(id: 'po1'));
      await tester.tap(find.byKey(const ValueKey('complete-production')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('operations-open-warning')),
        findsNothing,
      );
    });

    testWidgets('a release without the switch sends no flag', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_planner),
        'GET /api/v1/production/to-release': (_) => [_toRelease()],
        'POST /api/v1/production-orders': (_) => _order(),
      });
      await _pump(tester, http, const ReleasePage());
      await tester.tap(find.byKey(const ValueKey('release-button-ol1')));
      await tester.pumpAndSettle();
      final sent = http.bodies['POST /api/v1/production-orders']! as Map;
      expect(sent.containsKey('auto_release_subassemblies'), isFalse);
    });

    testWidgets('the switch on the release page is sent with the release', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_planner),
        'GET /api/v1/production/to-release': (_) => [_toRelease()],
        'POST /api/v1/production-orders': (_) => _order(),
      });
      await _pump(tester, http, const ReleasePage());
      await tester.tap(find.byKey(const ValueKey('auto-release')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('release-button-ol1')));
      await tester.pumpAndSettle();
      final sent = http.bodies['POST /api/v1/production-orders']! as Map;
      expect(sent['auto_release_subassemblies'], true);
    });

    testWidgets('the queue shows the progress of operations and what is behind', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_planner),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'GET /api/v1/production-orders': (_) => {
          'items': [
            _summary(operations: 5, operationsDone: 2, behind: true),
          ],
          'total': 1,
        },
      });
      await _pump(tester, http, const ProductionQueuePage());
      expect(find.byKey(const ValueKey('ops-po1')), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      expect(find.byKey(const ValueKey('behind-po1')), findsOneWidget);
      // The queue leads to the work centres and the capacity.
      await tester.tap(find.byKey(const ValueKey('capacity')));
      await tester.pumpAndSettle();
      // (The stub router answers every /production/... path with the detail page.)
      expect(find.text('production capacity'), findsOneWidget);
    });

    testWidgets('the work centres: the administrator adds one, others only look', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson([
          'production.read',
          'production.admin',
          'inventory.cost',
        ]),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'GET /api/v1/production/work-centres': (_) => [
          workCentre(
            hours: [
              {
                'weekday': 1,
                'start_time': '08:00:00',
                'end_time': '12:00:00',
              },
              {
                'weekday': 1,
                'start_time': '13:00:00',
                'end_time': '17:00:00',
              },
            ],
          ),
          workCentre(id: 'wc2', code: 'OLD', name: 'Old press', active: false),
        ],
        'POST /api/v1/production/work-centres': (_) => workCentre(),
      });
      await _pump(tester, http, const WorkCentresPage());
      final row = find.byKey(const ValueKey('work-centre-wc1'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('SAW · Saw')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('Welding')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('2 units')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('Cost per hour: 30')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('3 open operations')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('08:00–12:00, 13:00–17:00')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('work-centre-wc2')),
          matching: find.textContaining('No hours of its own'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('work-centre-wc2')),
          matching: find.textContaining('inactive'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('add-work-centre')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('wc-code')), 'CNC1');
      await tester.enterText(find.byKey(const ValueKey('wc-name')), 'Lathe');
      await tester.enterText(find.byKey(const ValueKey('wc-capacity')), '3');
      await tester.enterText(find.byKey(const ValueKey('wc-cost')), '45,5');
      await tester.tap(find.byKey(const ValueKey('wc-save')));
      await tester.pumpAndSettle();
      final sent = http.bodies['POST /api/v1/production/work-centres']! as Map;
      expect(sent['code'], 'CNC1');
      expect(sent['name'], 'Lathe');
      expect(sent['capacity'], 3);
      expect(sent['cost_per_hour'], '45.5');
      expect(sent['active'], true);
    });

    testWidgets('someone without the admin right sees work centres but cannot change them', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['production.read']),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'GET /api/v1/production/work-centres': (_) => [workCentre(cost: null)],
      });
      await _pump(tester, http, const WorkCentresPage());
      expect(find.byKey(const ValueKey('work-centre-wc1')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-work-centre')), findsNothing);
      expect(find.byKey(const ValueKey('delete-wc1')), findsNothing);
      expect(find.byKey(const ValueKey('hours-wc1')), findsNothing);
      expect(find.textContaining('Cost per hour'), findsNothing);
    });

    testWidgets('the opening hours are saved as blocks per weekday', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['production.read', 'production.admin']),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'GET /api/v1/production/work-centres': (_) => [workCentre()],
        'PUT /api/v1/production/work-centres/wc1/hours': (_) => workCentre(),
      });
      await _pump(tester, http, const WorkCentresPage());
      await tester.tap(find.byKey(const ValueKey('hours-wc1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No hours of its own'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('wc-add-block-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wc-add-block-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hours-save')));
      await tester.pumpAndSettle();
      final sent =
          http.bodies['PUT /api/v1/production/work-centres/wc1/hours']! as Map;
      expect(sent['slots'], [
        {'weekday': 1, 'start_time': '08:00:00', 'end_time': '12:00:00'},
        {'weekday': 1, 'start_time': '13:00:00', 'end_time': '17:00:00'},
      ]);
    });

    testWidgets('planners add and remove closures', (tester) async {
      final closure = {
        'id': 'cl1',
        'work_centre_id': null,
        'work_centre_code': null,
        'from_date': '2099-04-05',
        'to_date': '2099-04-05',
        'kind': 'holiday',
        'note': 'Easter Monday',
      };
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['production.read', 'production.write']),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'GET /api/v1/production/work-centres': (_) => [workCentre()],
        'GET /api/v1/production/closures': (_) => [closure],
        'POST /api/v1/production/closures': (_) => closure,
        'DELETE /api/v1/production/closures/cl1': (_) => <String, Object?>{},
      });
      await _pump(tester, http, const WorkCentresPage());
      await tester.tap(find.byKey(const ValueKey('closures')));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('closure-cl1'));
      expect(find.descendant(of: row, matching: find.text('Whole plant · Holiday')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('05/04/2099')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('Easter Monday')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('closure-note')), 'Overhaul');
      await tester.tap(find.byKey(const ValueKey('closure-add')));
      await tester.pumpAndSettle();
      final sent = http.bodies['POST /api/v1/production/closures']! as Map;
      expect(sent['kind'], 'maintenance');
      expect(sent['note'], 'Overhaul');
      expect(sent.containsKey('work_centre_id'), isFalse, reason: 'the whole plant');
      await tester.tap(find.byKey(const ValueKey('delete-closure-cl1')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/production/closures/cl1'));
    });

    Map<String, Object?> capacity() => {
      'from': '2099-03-01',
      'to': '2099-03-14',
      'centres': [
        {
          'id': 'wc1',
          'code': 'SAW',
          'name': 'Saw',
          'division_id': 'd1',
          'active': true,
          'capacity': 1,
          'days': [
            for (var i = 0; i < 14; i++)
              {
                'date': '2099-03-${(i + 1).toString().padLeft(2, '0')}',
                'available_minutes': i % 7 > 4 ? 0 : 480,
                'load_minutes': i == 0 ? 690 : (i == 1 ? 120 : 0),
                'overloaded': i == 0,
              },
          ],
          'total_available_minutes': 4800,
          'total_load_minutes': 810,
        },
      ],
    };

    testWidgets('capacity shows load against availability and flags overload', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['production.read']),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'GET /api/v1/production/capacity': (_) => capacity(),
      });
      await _pump(tester, http, const CapacityPage());
      // 690 minutes against 480: 11.5 of 8 hours, overloaded; 120 of 480 is 2 of 8.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('capacity-wc1-2099-03-01')),
          matching: find.text('11.5/8'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('capacity-wc1-2099-03-02')),
          matching: find.text('2/8'),
        ),
        findsOneWidget,
      );
      // A weekend: nothing available, nothing to do.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('capacity-wc1-2099-03-06')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      final overloaded = tester.widget<Container>(
        find.byKey(const ValueKey('capacity-wc1-2099-03-01')),
      );
      expect(overloaded.color, isNotNull);
      expect(find.textContaining('Red: overloaded'), findsOneWidget);
    });

    testWidgets('capacity moves a week at a time and can be limited to a division', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['production.read']),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'GET /api/v1/production/capacity': (_) => capacity(),
      });
      await _pump(tester, http, const CapacityPage());
      final first = DateTime.parse(
        http.queries.last['from'] as String,
      );
      expect(
        DateTime.parse(http.queries.last['to'] as String)
            .difference(first)
            .inDays,
        13,
        reason: 'two weeks',
      );
      await tester.tap(find.byKey(const ValueKey('capacity-later')));
      await tester.pumpAndSettle();
      expect(
        DateTime.parse(http.queries.last['from'] as String)
            .difference(first)
            .inDays,
        7,
      );
      await tester.tap(find.byKey(const ValueKey('capacity-today')));
      await tester.pumpAndSettle();
      expect(DateTime.parse(http.queries.last['from'] as String), first);
      await tester.tap(find.byKey(const ValueKey('capacity-division')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Welding').last);
      await tester.pumpAndSettle();
      expect(http.queries.last['division_id'], 'd1');
    });

    testWidgets('capacity is only for those who see production', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['helpdesk.read']),
        'GET /api/v1/production/divisions': (_) => [_division()],
        'GET /api/v1/production/capacity': (_) => capacity(),
      });
      await _pump(tester, http, const CapacityPage());
      expect(find.text('You do not have permission to change these settings.'), findsOneWidget);
    });
  });
}
