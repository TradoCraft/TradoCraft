import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/delivery/deliveries_page.dart';
import 'package:tradocraft_app/features/delivery/delivery_screen.dart';
import 'package:tradocraft_app/features/delivery/delivery_settings_page.dart';
import 'package:tradocraft_app/features/delivery/order_deliveries.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _line({
  String id = 'l1',
  String tracking = 'none',
  String? serialUnitId,
  String? serialNumber,
  String quantity = '5',
}) => {
  'id': id,
  'position': 1,
  'order_line_id': 'ol1',
  'order_position': 1,
  'product_id': 'p1',
  'product_code': 'FRAME',
  'product_name': 'Frame',
  'tracking': tracking,
  'quantity': quantity,
  'unit': 'pcs',
  'location_id': 'loc1',
  'location': 'WH1/MAIN',
  'lot_id': null,
  'lot_number': null,
  'serial_unit_id': serialUnitId,
  'serial_number': serialNumber,
  'stock_move_id': null,
};

Map<String, Object?> _note({
  String status = 'planned',
  String? plannedDate,
  List<Map<String, Object?>>? lines,
  Map<String, Object?>? closureWarning,
}) => {
  'id': 'n1',
  'number': 'DN2099-00001',
  'order_id': 'o1',
  'order_number': 'ORD-1',
  'order_revision': 1,
  'customer_id': 'c2',
  'customer_name': 'Bêta Industrie SA',
  'status': status,
  'planned_date': plannedDate,
  'ship_to': {
    'name': 'Bêta Industrie SA',
    'street': 'Rue 1',
    'postal_code': '4000',
    'city': 'Liège',
    'country_code': 'BE',
  },
  'carrier': 'DHL',
  'tracking_number': '',
  'notes': '',
  'planned_on_closure': false,
  'closure_override_reason': null,
  'closure_warning': closureWarning,
  'shipped_at': status == 'shipped' ? '2099-01-02T10:00:00Z' : null,
  'created_at': '2099-01-01T10:00:00Z',
  'updated_at': '2099-01-01T10:00:00.000000Z',
  'lines': lines ?? [_line()],
};

Map<String, Object?> _summary({
  String id = 'n1',
  String status = 'planned',
  bool onClosure = false,
}) => {
  'id': id,
  'number': 'DN2099-00001',
  'order_id': 'o1',
  'order_number': 'ORD-1',
  'customer_id': 'c2',
  'customer_name': 'Bêta Industrie SA',
  'status': status,
  'planned_date': '2099-06-11',
  'carrier': 'DHL',
  'tracking_number': 'TRK-1',
  'planned_on_closure': onClosure,
  'line_count': 1,
  'shipped_at': null,
  'created_at': '2099-01-01T10:00:00Z',
};

/// The customer is closed 10 to 12 June 2099; the next open day is the 13th.
Map<String, Object?> _closedCheck() => {
  'date': '2099-06-11',
  'closed': true,
  'closure': {
    'id': 'cl1',
    'customer_id': 'c2',
    'customer_code': 'C0002',
    'customer_name': 'Bêta Industrie SA',
    'starts_on': '2099-06-10',
    'ends_on': '2099-06-12',
    'kind': 'collective_leave',
    'notes': '',
    'source': 'staff',
    'created_at': '2026-11-09T10:00:00Z',
  },
  'next_open_day': '2099-06-13',
};

Map<String, Object?> _openCheck() => {
  'date': '2099-06-13',
  'closed': false,
  'closure': null,
  'next_open_day': '2099-06-13',
};

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: '/delivery/:id',
        builder: (_, s) =>
            Scaffold(body: Text('note ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/delivery/settings',
        builder: (_, _) => const Scaffold(body: Text('settings page')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
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

const _planner = [
  'customers.read',
  'delivery.read',
  'delivery.write',
  'delivery.ship',
];

FakeHttp _screenHttp({
  required List<String> perms,
  String policy = 'warn',
  Map<String, Object?>? note,
  Object? Function(Object?)? onShip,
}) {
  return FakeHttp({
    'GET /api/v1/me': (_) => meJson(perms),
    'GET /api/v1/deliveries/n1': (_) => note ?? _note(),
    'GET /api/v1/delivery/settings': (_) => {'closure_policy': policy},
    'GET /api/v1/customers/c2/closures/check': (_) => _closedCheck(),
    // Like the server: answers with what was saved.
    'PUT /api/v1/deliveries/n1': (b) {
      final body = b! as Map;
      final stored = note ?? _note();
      final base = (stored['lines']! as List).cast<Map<String, Object?>>();
      final sent = body['lines'] as List?;
      return {
        ...stored,
        'planned_date': (body['planned_date'] as String?)?.substring(0, 10),
        'carrier': body['carrier'],
        'tracking_number': body['tracking_number'],
        'updated_at': '2099-01-02T10:00:00.000000Z',
        if (sent != null)
          'lines': [
            for (final s in sent.cast<Map>())
              {
                ...base.firstWhere(
                  (l) => l['order_line_id'] == s['order_line_id'],
                ),
                'quantity': s['quantity'],
                'serial_unit_id': s['serial_unit_id'],
                'serial_number': s['serial_unit_id'] == 'u1' ? 'P-001' : null,
              },
          ],
      };
    },
    'POST /api/v1/deliveries/n1/ship':
        onShip ?? (_) => _note(status: 'shipped'),
  });
}

/// Opens the date picker and takes the day it offers.
Future<void> _pickDay(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('planned-date')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the list shows planned deliveries, marks closures, and offers settings to the admin',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['delivery.read', 'delivery.admin']),
        'GET /api/v1/deliveries': (_) => {
          'items': [_summary(onClosure: true)],
          'total': 1,
        },
      });
      await _pump(tester, http, const DeliveriesPage());
      expect(find.text('DN2099-00001'), findsWidgets);
      expect(find.text('ORD-1'), findsWidgets);
      expect(http.queries.last['status'], 'planned', reason: 'open work first');
      expect(find.byTooltip('on a closure'), findsOneWidget);
      expect(find.byKey(const ValueKey('delivery-settings')), findsOneWidget);
    },
  );

  testWidgets('a reader gets no settings button', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['delivery.read']),
      'GET /api/v1/deliveries': (_) => {'items': <Object?>[], 'total': 0},
    });
    await _pump(tester, http, const DeliveriesPage());
    expect(find.byKey(const ValueKey('delivery-settings')), findsNothing);
  });

  testWidgets('the administrator chooses the closure policy', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['delivery.read', 'delivery.admin']),
      'GET /api/v1/delivery/settings': (_) => {'closure_policy': 'warn'},
      'PUT /api/v1/delivery/settings': (b) => b,
    });
    await _pump(tester, http, const DeliverySettingsPage());
    expect(find.text('Warn only'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('policy-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();
    expect(http.bodies['PUT /api/v1/delivery/settings'], {
      'closure_policy': 'block',
    });
  });

  testWidgets('others cannot change the settings', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['delivery.read']),
      'GET /api/v1/delivery/settings': (_) => {'closure_policy': 'warn'},
    });
    await _pump(tester, http, const DeliverySettingsPage());
    expect(find.byKey(const ValueKey('save-settings')), findsNothing);
    expect(find.textContaining('permission'), findsOneWidget);
  });

  testWidgets(
    'warn: a date on a closure shows a warning and can still be saved',
    (tester) async {
      final http = _screenHttp(perms: _planner);
      await _pump(tester, http, const DeliveryScreen(id: 'n1'));
      expect(find.byKey(const ValueKey('closure-banner')), findsNothing);

      await _pickDay(tester);
      expect(find.byKey(const ValueKey('closure-banner')), findsOneWidget);
      expect(
        find.textContaining('closed from 10/06/2099 to 12/06/2099'),
        findsOneWidget,
      );
      expect(find.text('Use 13/06/2099'), findsOneWidget);
      expect(find.textContaining('not allowed'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('save-delivery')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('PUT /api/v1/deliveries/n1'));
    },
  );

  testWidgets('block: saving is held back until another day is chosen', (
    tester,
  ) async {
    final http = _screenHttp(perms: _planner, policy: 'block');
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    await _pickDay(tester);
    expect(find.textContaining('not allowed'), findsOneWidget);
    final save = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('save-delivery')),
    );
    expect(save.onPressed, isNull);
    final ship = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ship-delivery')),
    );
    expect(ship.onPressed, isNull);
  });

  testWidgets('the next open day replaces the date and clears the warning', (
    tester,
  ) async {
    var open = false;
    final http = _screenHttp(perms: _planner, policy: 'block');
    http.routes['GET /api/v1/customers/c2/closures/check'] = (_) =>
        open ? _openCheck() : _closedCheck();
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    await _pickDay(tester);
    open = true;
    await tester.tap(find.byKey(const ValueKey('use-next-open-day')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('closure-banner')), findsNothing);
    expect(find.textContaining('13/06/2099'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('save-delivery')));
    await tester.pumpAndSettle();
    final sent = http.bodies['PUT /api/v1/deliveries/n1']! as Map;
    expect((sent['planned_date'] as String).startsWith('2099-06-13'), isTrue);
  });

  testWidgets('override: a reason and the right to override are needed', (
    tester,
  ) async {
    final http = _screenHttp(
      perms: [..._planner, 'delivery.override_closure'],
      policy: 'override',
    );
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    await _pickDay(tester);
    OutlinedButton save() => tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('save-delivery')),
    );
    expect(save().onPressed, isNull, reason: 'a reason is needed');
    await tester.enterText(
      find.byKey(const ValueKey('override-reason')),
      'they receive on request',
    );
    await tester.pumpAndSettle();
    expect(save().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('save-delivery')));
    await tester.pumpAndSettle();
    final sent = http.bodies['PUT /api/v1/deliveries/n1']! as Map;
    expect(sent['closure_override_reason'], 'they receive on request');
  });

  testWidgets('override without the right shows why and stays blocked', (
    tester,
  ) async {
    final http = _screenHttp(perms: _planner, policy: 'override');
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    await _pickDay(tester);
    expect(find.textContaining('right to override'), findsOneWidget);
    final save = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('save-delivery')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets(
    'shipping saves the note first and sends the tracking reference',
    (tester) async {
      final http = _screenHttp(perms: _planner);
      await _pump(tester, http, const DeliveryScreen(id: 'n1'));
      await tester.enterText(
        find.byKey(const ValueKey('tracking')),
        'JVGL0001',
      );
      await tester.tap(find.byKey(const ValueKey('ship-delivery')));
      await tester.pumpAndSettle();
      expect(
        http.requests.where((r) => r.contains('/deliveries/n1')).toList(),
        [
          'GET /api/v1/deliveries/n1',
          'PUT /api/v1/deliveries/n1',
          'POST /api/v1/deliveries/n1/ship',
        ],
      );
      final put = http.bodies['PUT /api/v1/deliveries/n1']! as Map;
      expect(put['lines'], [
        {'order_line_id': 'ol1', 'quantity': '5', 'location_id': 'loc1'},
      ]);
      final ship = http.bodies['POST /api/v1/deliveries/n1/ship']! as Map;
      expect(ship['tracking_number'], 'JVGL0001');
      expect(find.text('Delivery shipped'), findsOneWidget);
      expect(find.byKey(const ValueKey('ship-delivery')), findsNothing);
    },
  );

  testWidgets('a serial-tracked line gets its serial number before shipping', (
    tester,
  ) async {
    final http = _screenHttp(
      perms: _planner,
      note: _note(
        lines: [_line(tracking: 'serial', quantity: '1')],
      ),
    );
    // Offered by the delivery, for the location of the pick: no right to read serials is needed.
    http.routes['GET /api/v1/deliveries/n1/lines/l1/serial-units'] = (_) => [
      {'id': 'u1', 'serial_number': 'P-001'},
    ];
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    await tester.tap(find.byKey(const ValueKey('serial-l1')));
    await tester.pumpAndSettle();
    expect(
      http.requests,
      contains('GET /api/v1/deliveries/n1/lines/l1/serial-units'),
    );
    expect(http.requests, isNot(contains('GET /api/v1/serials')));
    await tester.tap(find.byKey(const ValueKey('unit-u1')));
    await tester.pumpAndSettle();
    expect(find.text('P-001'), findsOneWidget);
    // Saving shows what the server answered: the chosen serial number survives.
    await tester.tap(find.byKey(const ValueKey('save-delivery')));
    await tester.pumpAndSettle();
    expect(find.textContaining('P-001'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('ship-delivery')));
    await tester.pumpAndSettle();
    final put = http.bodies['PUT /api/v1/deliveries/n1']! as Map;
    expect((put['lines'] as List).first['serial_unit_id'], 'u1');
  });

  testWidgets('the version of the note is sent, and a stale save is refused', (
    tester,
  ) async {
    final http = _screenHttp(perms: _planner);
    http.routes['PUT /api/v1/deliveries/n1'] = (_) => const FakeStatus(409, {
      'error': 'conflict',
      'code': 'delivery_note_changed',
      'message': 'delivery note DN2099-00001 was changed by someone else; reload it before saving',
    });
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    await tester.tap(find.byKey(const ValueKey('save-delivery')));
    await tester.pumpAndSettle();
    final sent = http.bodies['PUT /api/v1/deliveries/n1']! as Map;
    expect(sent['expected_updated_at'], startsWith('2099-01-01T10:00:00'));
    expect(find.textContaining('changed by someone else'), findsOneWidget);
    // Shipping stops there: nothing is shipped from a stale picking list.
    await tester.tap(find.byKey(const ValueKey('ship-delivery')));
    await tester.pumpAndSettle();
    expect(http.requests, isNot(contains('POST /api/v1/deliveries/n1/ship')));
  });

  testWidgets(
    'without the right to read closures the saved warning still shows',
    (tester) async {
      final closure = (_closedCheck()['closure']! as Map)
          .cast<String, Object?>();
      final http = _screenHttp(
        perms: ['delivery.read', 'delivery.write', 'delivery.ship'],
        note: _note(
          plannedDate: '2099-06-11',
          closureWarning: {'closure': closure, 'next_open_day': '2099-06-13'},
        ),
      );
      http.routes.remove('GET /api/v1/customers/c2/closures/check');
      await _pump(tester, http, const DeliveryScreen(id: 'n1'));
      expect(find.byKey(const ValueKey('closure-banner')), findsOneWidget);
      expect(find.text('Use 13/06/2099'), findsOneWidget);
    },
  );

  testWidgets('a line can be removed and its quantity changed', (tester) async {
    final http = _screenHttp(perms: _planner);
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    await tester.tap(find.byTooltip('Quantity'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('line-quantity')), '2,5');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-delivery')));
    await tester.pumpAndSettle();
    var put = http.bodies['PUT /api/v1/deliveries/n1']! as Map;
    expect((put['lines'] as List).first['quantity'], '2.5');

    await tester.tap(find.byKey(const ValueKey('remove-l1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing to deliver yet'), findsOneWidget);
    final ship = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ship-delivery')),
    );
    expect(ship.onPressed, isNull, reason: 'an empty note cannot ship');
    await tester.tap(find.byKey(const ValueKey('save-delivery')));
    await tester.pumpAndSettle();
    put = http.bodies['PUT /api/v1/deliveries/n1']! as Map;
    expect(put['lines'], isEmpty);
  });

  testWidgets('a shipped note is read-only', (tester) async {
    final http = _screenHttp(
      perms: [..._planner, 'delivery.admin'],
      note: _note(status: 'shipped', plannedDate: '2099-06-13'),
    );
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    expect(find.byKey(const ValueKey('save-delivery')), findsNothing);
    expect(find.byKey(const ValueKey('ship-delivery')), findsNothing);
    expect(find.byKey(const ValueKey('cancel-delivery')), findsNothing);
    expect(find.byKey(const ValueKey('delivery-pdf')), findsOneWidget);
    expect(
      http.requests,
      isNot(contains('GET /api/v1/customers/c2/closures/check')),
    );
  });

  testWidgets('a server refusal is shown and the note stays as it was', (
    tester,
  ) async {
    final http = _screenHttp(perms: _planner);
    http.routes['PUT /api/v1/deliveries/n1'] = (_) => const FakeStatus(409, {
      'error': 'conflict',
      'code': 'customer_closed',
      'message': 'the customer is closed on 2099-06-11',
    });
    await _pump(tester, http, const DeliveryScreen(id: 'n1'));
    await tester.tap(find.byKey(const ValueKey('save-delivery')));
    await tester.pumpAndSettle();
    expect(find.textContaining('the customer is closed'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-delivery')), findsOneWidget);
  });

  testWidgets('the order lists its deliveries and plans the next one', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['delivery.read', 'delivery.write']),
      'GET /api/v1/orders/o1/deliveries': (_) => [_summary(status: 'shipped')],
      'POST /api/v1/orders/o1/deliveries': (_) => _note(),
    });
    await _pump(
      tester,
      http,
      const OrderDeliveries(orderId: 'o1', orderStatus: 'partially_shipped'),
    );
    expect(find.textContaining('DN2099-00001 · shipped'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-delivery')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/orders/o1/deliveries'));
    expect(find.text('note n1'), findsOneWidget, reason: 'opens the new note');
  });

  testWidgets('a reader of deliveries cannot plan one on a deliverable order', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['delivery.read']),
      'GET /api/v1/orders/o1/deliveries': (_) => <Object?>[],
    });
    await _pump(
      tester,
      http,
      const OrderDeliveries(orderId: 'o1', orderStatus: 'confirmed'),
    );
    expect(find.byKey(const ValueKey('new-delivery')), findsNothing);
  });

  testWidgets(
    'no new delivery on an order that cannot ship or without the right',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['delivery.read', 'delivery.write']),
        'GET /api/v1/orders/o1/deliveries': (_) => <Object?>[],
      });
      await _pump(
        tester,
        http,
        const OrderDeliveries(orderId: 'o1', orderStatus: 'shipped'),
      );
      expect(find.byKey(const ValueKey('new-delivery')), findsNothing);
    },
  );
}
