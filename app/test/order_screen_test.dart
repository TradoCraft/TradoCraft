import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/orders/order_screen.dart';
import 'package:tradocraft_app/features/orders/orders_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _line(String pos, {String pricing = 'list'}) => {
  'id': 'line$pos',
  'position': int.parse(pos),
  'product_id': 'p$pos',
  'product_code': 'UNIT-$pos',
  'description': 'Process unit $pos',
  'unit': 'pcs',
  'quantity': '1',
  'list_unit_price': '3880.0000',
  'line_discount_percent': '0',
  'pricing_type': pricing,
  'rebate_percent': '5',
  'net_unit_price': '3686.0000',
  'line_total': '3686.00',
  'vat_rate': '21',
};

Map<String, Object?> _summary(
  String status, {
  String priority = 'normal',
  int current = 1,
  String purpose = 'installation',
  String country = 'NL',
  String? gridId,
}) => {
  'id': 'o1',
  'number': 'O2026-00001',
  'status': status,
  'current_revision': current,
  'priority': priority,
  'quotation_id': 'q1',
  'quotation_number': 'Q2026-00001',
  'quotation_revision': 1,
  'customer_id': 'c1',
  'customer_name': 'Alpha Installaties NV',
  'customer_reference': 'PO-77',
  'order_date': '2026-11-06',
  'purpose': purpose,
  'delivery_country_code': country,
  'power_grid_id': gridId,
  'salesperson_id': 'u',
  'salesperson_name': 'Sales',
  'currency': 'EUR',
  'subtotal': '3686.00',
  'total': '4460.06',
};

Map<String, Object?> _order(
  String status, {
  String priority = 'normal',
  bool net = false,
  int revision = 1,
  int current = 1,
  String purpose = 'installation',
  String country = 'NL',
  String? gridId,
}) => {
  'order': _summary(
    status,
    priority: priority,
    current: current,
    purpose: purpose,
    country: country,
    gridId: gridId,
  ),
  'revision': revision,
  'revision_status': status,
  'created_at': '2026-11-06T09:00:00Z',
  'notes': 'Deliver on pallets',
  'cancel_reason': status == 'cancelled' ? 'Customer withdrew' : '',
  'confirmation_note': status == 'confirmed' ? 'By phone' : '',
  'confirmed_at': status == 'confirmed' ? '2026-11-07T09:00:00Z' : null,
  'confirmed_by': status == 'confirmed' ? 'u' : null,
  'confirmed_revision': status == 'confirmed' ? 1 : null,
  'confirmed_via': status == 'confirmed' ? 'staff' : null,
  'vat_total': '774.06',
  'lines': [_line('1', pricing: net ? 'net' : 'list')],
  'warnings': <Object?>[],
  'suggestions': <Object?>[],
  'revisions': [
    for (var r = 1; r <= current; r++)
      {
        'revision': r,
        'status': r == current ? status : 'superseded',
        'created_at': '2026-11-06T09:00:00Z',
        'sent_at': null,
        'sent_to': null,
        'subtotal': '3686.00',
        'total': '4460.06',
      },
  ],
};

Map<String, Object?> _request({String status = 'open'}) => {
  'id': 'r1',
  'order_id': 'o1',
  'requested_by_contact_id': 'p1',
  'requested_by_name': 'Sofie Maes',
  'requested_priority': 'expedite',
  'message': 'We need it next week',
  'status': status,
  'resolution_note': '',
  'created_at': '2026-11-08T09:00:00Z',
  'resolved_at': null,
};

Map<String, Object?> _grid(String id, int voltage, {bool active = true}) => {
  'id': id,
  'country_code': 'NL',
  'name': 'NL $voltage',
  'voltage_v': voltage,
  'phases': voltage > 300 ? 3 : 1,
  'frequency_hz': 50,
  'active': active,
};

FakeHttp _http(
  String status, {
  String priority = 'normal',
  List<String> perms = const ['orders.read', 'orders.write'],
  bool net = false,
  int current = 1,
  List<Object?> requests = const [],
  Map<String, Object? Function(Object?)> extra = const {},
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/orders/o1': (_) => _order(
    status,
    priority: priority,
    net: net,
    current: current,
    revision: current,
  ),
  'GET /api/v1/orders/o1/revisions/1': (_) =>
      _order('superseded', current: current),
  'GET /api/v1/orders/o1/priority-history': (_) => [
    {
      'id': 'h1',
      'old_priority': 'normal',
      'new_priority': 'expedite',
      'reason': 'Key account',
      'changed_by': 'u',
      'changed_by_name': 'Sales',
      'changed_at': '2026-11-07T09:00:00Z',
    },
  ],
  'GET /api/v1/orders/o1/priority-requests': (_) => requests,
  'PUT /api/v1/orders/o1': (_) => _order('draft'),
  'POST /api/v1/orders/o1/send': (_) => _order('sent'),
  'POST /api/v1/orders/o1/revisions': (_) =>
      _order('draft', current: 2, revision: 2),
  'POST /api/v1/orders/o1/confirm': (_) => _order('confirmed'),
  'POST /api/v1/orders/o1/cancel': (_) => _order('cancelled'),
  'PUT /api/v1/orders/o1/priority': (_) => _order(status, priority: 'expedite'),
  'POST /api/v1/orders/o1/priority-requests/r1/dismiss': (_) =>
      _request(status: 'dismissed'),
  ...extra,
});

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => home)],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<FakeHttp> _screen(
  WidgetTester tester,
  String status, {
  String priority = 'normal',
  List<String> perms = const ['orders.read', 'orders.write'],
  bool net = false,
  int current = 1,
  List<Object?> requests = const [],
  Map<String, Object? Function(Object?)> extra = const {},
}) async {
  final http = _http(
    status,
    priority: priority,
    perms: perms,
    net: net,
    current: current,
    requests: requests,
    extra: extra,
  );
  await _pump(tester, http, const OrderScreen(id: 'o1'));
  return http;
}

void main() {
  testWidgets('a draft can be edited and sent, not revised or confirmed', (
    tester,
  ) async {
    await _screen(tester, 'draft');
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Send order confirmation'), findsOneWidget);
    expect(find.text('New revision'), findsNothing);
    expect(find.text('Confirm on behalf of customer'), findsNothing);
    expect(find.text('Revision 1'), findsWidgets);
  });

  testWidgets('editing a draft puts quantities and discounts in the PUT', (
    tester,
  ) async {
    final http = await _screen(tester, 'draft');
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    // Fields: reference, notes, description, quantity, discount.
    await tester.enterText(find.widgetWithText(TextField, '1'), '3');
    await tester.enterText(find.widgetWithText(TextField, '0'), '2,5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
    final line = (body['lines'] as List).single as Map;
    expect(line['quantity'], '3');
    expect(line['line_discount_percent'], '2.5');
    expect(line['position'], 1);
    expect(body['notes'], 'Deliver on pallets');
    expect(find.text('Order saved.'), findsOneWidget);
  });

  testWidgets(
    'editing reports unsaved changes to its tab until saved or cancelled',
    (tester) async {
      final dirty = ValueNotifier(false);
      await _pump(
        tester,
        _http('draft'),
        TabScope(
          id: 1,
          active: true,
          dirty: dirty,
          setTitle: (_) {},
          child: const OrderScreen(id: 'o1'),
        ),
      );
      expect(dirty.value, isFalse);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(dirty.value, isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(dirty.value, isFalse);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(dirty.value, isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(dirty.value, isFalse);
    },
  );

  testWidgets('a draft shows purpose and country and edits them in the PUT', (
    tester,
  ) async {
    final http = await _screen(tester, 'draft');
    expect(find.text('Installation'), findsOneWidget);
    expect(find.text('NL'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('deliveryCountry')), 'de');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
    expect(body['purpose'], 'stock');
    expect(body['delivery_country_code'], 'DE');
  });

  group('power grid in edit mode', () {
    Map<String, Object? Function(Object?)> grids({
      String purpose = 'installation',
      String? gridId,
      List<Object?>? list,
    }) => {
      'GET /api/v1/orders/o1': (_) =>
          _order('draft', purpose: purpose, gridId: gridId),
      'GET /api/v1/power-grids': (_) =>
          list ?? [_grid('g1', 230), _grid('g2', 400)],
    };

    testWidgets('is offered with two active grids and its id is sent', (
      tester,
    ) async {
      final http = await _screen(tester, 'draft', extra: grids());
      expect(find.text('Power grid'), findsNothing, reason: 'read-only view');
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Power grid'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('grid-NL-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('400 V 3ph 50 Hz').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
      expect(body['power_grid_id'], 'g2');
      expect(body.containsKey('clear_power_grid'), isFalse);
    });

    testWidgets('any grid over a stored grid sends clear_power_grid', (
      tester,
    ) async {
      final http = await _screen(tester, 'draft', extra: grids(gridId: 'g2'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grid-NL-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any grid in this country').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
      expect(body['clear_power_grid'], true);
      expect(body.containsKey('power_grid_id'), isFalse);
    });

    testWidgets('the stored grid is kept (and sent) when left alone', (
      tester,
    ) async {
      final http = await _screen(tester, 'draft', extra: grids(gridId: 'g2'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
      expect(body['power_grid_id'], 'g2');
      expect(body.containsKey('clear_power_grid'), isFalse);
    });

    testWidgets('changing the country drops the grid and asks for the new '
        'country grids', (tester) async {
      final http = await _screen(tester, 'draft', extra: grids(gridId: 'g2'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('deliveryCountry')),
        'fr',
      );
      await tester.pumpAndSettle();
      expect(http.queries.last['country'], 'FR');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
      expect(body['delivery_country_code'], 'FR');
      expect(body.containsKey('power_grid_id'), isFalse);
    });

    testWidgets('is hidden with fewer than two active grids', (tester) async {
      await _screen(
        tester,
        'draft',
        extra: grids(list: [_grid('g1', 230), _grid('g2', 400, active: false)]),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Power grid'), findsNothing);
    });

    testWidgets('is hidden for a stock purpose and when switching to it', (
      tester,
    ) async {
      final http = await _screen(
        tester,
        'draft',
        extra: grids(purpose: 'stock', gridId: 'g2'),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Power grid'), findsNothing);
      await tester.tap(find.text('Installation'));
      await tester.pumpAndSettle();
      expect(find.text('Power grid'), findsOneWidget);
      await tester.tap(find.text('Stock'));
      await tester.pumpAndSettle();
      expect(find.text('Power grid'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
      expect(body['purpose'], 'stock');
      expect(body.containsKey('power_grid_id'), isFalse);
      expect(body.containsKey('clear_power_grid'), isFalse);
    });

    testWidgets('is not part of the read-only view of a sent order', (
      tester,
    ) async {
      await _screen(
        tester,
        'sent',
        extra: {
          'GET /api/v1/power-grids': (_) => [
            _grid('g1', 230),
            _grid('g2', 400),
          ],
        },
      );
      expect(find.text('Power grid'), findsNothing);
    });
  });

  testWidgets('purpose and country are read-only once the order is sent', (
    tester,
  ) async {
    await _screen(tester, 'sent');
    expect(find.text('Installation'), findsOneWidget);
    expect(find.text('NL'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.byKey(const ValueKey('purpose')), findsNothing);
    expect(find.byKey(const ValueKey('deliveryCountry')), findsNothing);
  });

  testWidgets('net-priced lines have no discount field', (tester) async {
    final http = await _screen(tester, 'draft', net: true);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
    expect(
      ((body['lines'] as List).single as Map)['line_discount_percent'],
      isNull,
    );
  });

  testWidgets('removing a line leaves it out of the PUT', (tester) async {
    final http = await _screen(tester, 'draft');
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/orders/o1'] as Map;
    expect(body['lines'], isEmpty);
  });

  testWidgets('sending the order confirmation posts to /send', (tester) async {
    final http = await _screen(tester, 'draft');
    await tester.tap(find.text('Send order confirmation'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/orders/o1/send'));
    expect(find.text('Order confirmation queued for sending.'), findsOneWidget);
  });

  testWidgets('a refused send shows the server message', (tester) async {
    final http = _http('draft');
    // Without a route the fake answers with an error body, like a refused send.
    http.routes.remove('POST /api/v1/orders/o1/send');
    await _pump(tester, http, const OrderScreen(id: 'o1'));
    await tester.tap(find.text('Send order confirmation'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('POST /api/v1/orders/o1/send'), findsOneWidget);
  });

  testWidgets('a sent order offers new revision and confirm, not edit', (
    tester,
  ) async {
    await _screen(tester, 'sent');
    expect(find.text('New revision'), findsOneWidget);
    expect(find.text('Confirm on behalf of customer'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Send order confirmation'), findsNothing);
  });

  testWidgets('a new revision is requested and shown', (tester) async {
    final http = await _screen(tester, 'sent');
    await tester.tap(find.text('New revision'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/orders/o1/revisions'));
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('confirming on behalf posts the note and revision', (
    tester,
  ) async {
    final http = await _screen(tester, 'sent');
    await tester.tap(find.text('Confirm on behalf of customer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, ' By phone ');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/orders/o1/confirm'] as Map;
    expect(body['note'], 'By phone');
    expect(body['revision'], 1);
    expect(find.text('Order confirmed.'), findsOneWidget);
  });

  testWidgets('confirming shows the returned warnings and suggestions', (
    tester,
  ) async {
    await _screen(
      tester,
      'sent',
      extra: {
        'POST /api/v1/orders/o1/confirm': (_) => {
          ..._order('confirmed'),
          'warnings': [
            {
              'kind': 'power_grid',
              'product_code': 'UNIT-1',
              'message': 'm',
              'details': {
                'status': 'unknown_grid',
                'country_code': 'NL',
                'supported': <Object?>[],
                'available': <Object?>[],
              },
            },
          ],
          'suggestions': [
            {
              'product_id': 'p9',
              'product_code': 'CTRL-9',
              'product_name': 'Controller 9',
              'reason': 'often_bought_together',
              'because_of_code': 'UNIT-1',
              'note': '',
              'confidence': 0.5,
            },
          ],
        },
      },
    );
    await tester.tap(find.text('Confirm on behalf of customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('Warnings and suggestions'), findsOneWidget);
    expect(find.textContaining('No grid data for NL'), findsOneWidget);
    expect(find.text('CTRL-9 · Controller 9'), findsOneWidget);
    expect(find.text('Often bought together'), findsOneWidget);
    // Suggestions cannot be added to a confirmed order.
    expect(find.widgetWithText(OutlinedButton, 'Add'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Warnings and suggestions'), findsNothing);
  });

  testWidgets('confirming without warnings opens no dialog', (tester) async {
    await _screen(tester, 'sent');
    await tester.tap(find.text('Confirm on behalf of customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('Warnings and suggestions'), findsNothing);
    expect(find.text('Order confirmed.'), findsOneWidget);
  });

  testWidgets('a confirmed order cannot be revised and shows confirmation', (
    tester,
  ) async {
    await _screen(tester, 'confirmed');
    expect(find.text('New revision'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Confirm on behalf of customer'), findsNothing);
    expect(find.text('Cancel order'), findsOneWidget);
    expect(find.text('staff, on behalf of the customer'), findsOneWidget);
    expect(find.text('By phone'), findsOneWidget);
  });

  testWidgets('cancelling needs a reason and posts it', (tester) async {
    final http = await _screen(tester, 'confirmed');
    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('A reason is required.'), findsOneWidget);
    expect(http.requests, isNot(contains('POST /api/v1/orders/o1/cancel')));

    await tester.enterText(find.byType(TextField).last, 'Customer withdrew');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/orders/o1/cancel'] as Map;
    expect(body['reason'], 'Customer withdrew');
  });

  testWidgets('a cancelled order is read-only and shows the reason', (
    tester,
  ) async {
    await _screen(tester, 'cancelled');
    expect(find.text('Cancelled: Customer withdrew'), findsOneWidget);
    expect(find.text('Cancel order'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('New revision'), findsNothing);
    expect(find.text('Change priority'), findsNothing);
  });

  testWidgets('without orders.write there are no write actions', (
    tester,
  ) async {
    await _screen(tester, 'sent', perms: ['orders.read']);
    expect(find.text('New revision'), findsNothing);
    expect(find.text('Confirm on behalf of customer'), findsNothing);
    expect(find.text('Cancel order'), findsNothing);
    expect(find.text('Change priority'), findsNothing);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('an older revision opens read-only', (tester) async {
    final http = await _screen(tester, 'sent', current: 2);
    await tester.tap(find.textContaining('Revision 1 ·'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('GET /api/v1/orders/o1/revisions/1'));
    expect(find.textContaining('You are viewing revision 1'), findsOneWidget);
    expect(find.text('New revision'), findsNothing);
    expect(find.text('Confirm on behalf of customer'), findsNothing);
    await tester.tap(find.text('Back to current revision'));
    await tester.pumpAndSettle();
    expect(find.text('New revision'), findsOneWidget);
  });

  testWidgets('changing the priority requires a reason', (tester) async {
    final http = await _screen(tester, 'confirmed');
    expect(find.text('normal'), findsWidgets);
    expect(find.textContaining('normal → expedite by Sales'), findsOneWidget);

    await tester.tap(find.text('Change priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('A reason is required.'), findsOneWidget);
    expect(http.requests, isNot(contains('PUT /api/v1/orders/o1/priority')));

    await tester.enterText(find.byType(TextField).last, 'Key account');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/orders/o1/priority'] as Map;
    expect(body['priority'], 'expedite');
    expect(body['reason'], 'Key account');
    expect(body['request_id'], isNull);
  });

  testWidgets('applying a customer request sends its message and id', (
    tester,
  ) async {
    final http = await _screen(tester, 'confirmed', requests: [_request()]);
    expect(find.text('Sofie Maes asks for priority: expedite'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/orders/o1/priority'] as Map;
    expect(body['priority'], 'expedite');
    expect(body['reason'], 'We need it next week');
    expect(body['request_id'], 'r1');
    // The list refreshes afterwards.
    expect(
      http.requests.where(
        (r) => r == 'GET /api/v1/orders/o1/priority-requests',
      ),
      hasLength(2),
    );
  });

  testWidgets('dismissing a customer request posts the note', (tester) async {
    final http = await _screen(tester, 'confirmed', requests: [_request()]);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Not possible');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    const key = 'POST /api/v1/orders/o1/priority-requests/r1/dismiss';
    expect((http.bodies[key] as Map)['note'], 'Not possible');
  });

  testWidgets('the order list filters on status and shows priority', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/orders': (_) => {
        'items': [_summary('sent', priority: 'expedite', current: 2)],
        'total': 1,
        'limit': 50,
        'offset': 0,
      },
    });
    await _pump(tester, http, const Scaffold(body: OrdersPage()));
    expect(find.text('O2026-00001  r2'), findsOneWidget);
    expect(find.text('expedite'), findsOneWidget);
    expect(find.text('sent'), findsOneWidget);

    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('confirmed').last);
    await tester.pumpAndSettle();
    expect(http.queries.first['status'], isNull);
    expect(http.queries.last['status'], 'confirmed');
  });

  Map<String, Object?> availability({bool reservable = true}) => {
    'order_id': 'o1',
    'order_number': 'SO2026-00001',
    'order_status': reservable ? 'confirmed' : 'sent',
    'reservable': reservable,
    'lines': [
      {
        'order_line_id': 'line1',
        'position': 1,
        'product_id': 'p1',
        'product_code': 'UNIT-1',
        'description': 'Process unit 1',
        'unit': 'pcs',
        'ordered': '1.0000',
        'ordered_stock': '1.0000',
        'consumed': '0.0000',
        'reserved': '0.0000',
        'on_hand': '3.0000',
        'expired': '0.0000',
        'reserved_total': '1.0000',
        'available': '2.0000',
        'shortfall': '0.0000',
        'state': 'available',
      },
      {
        'order_line_id': 'line2',
        'position': 2,
        'product_id': 'p2',
        'product_code': 'HOSE-25',
        'description': 'Hose',
        'unit': 'm',
        'ordered': '10.0000',
        'ordered_stock': '10.0000',
        'consumed': '0.0000',
        'reserved': '4.0000',
        'on_hand': '4.0000',
        'expired': '2.0000',
        'reserved_total': '4.0000',
        'available': '0.0000',
        'shortfall': '6.0000',
        'state': 'partial',
      },
      {
        'order_line_id': 'line3',
        'position': 3,
        'product_id': null,
        'product_code': 'INSTALL',
        'description': 'Installation',
        'unit': 'h',
        'ordered': '2.0000',
        'ordered_stock': '0.0000',
        'consumed': '0.0000',
        'reserved': '0.0000',
        'on_hand': '0.0000',
        'expired': '0.0000',
        'reserved_total': '0.0000',
        'available': '0.0000',
        'shortfall': '0.0000',
        'state': 'not_stocked',
      },
    ],
  };

  testWidgets('the order shows availability per line and reserves stock', (
    tester,
  ) async {
    final http = await _screen(
      tester,
      'confirmed',
      perms: const ['orders.read', 'inventory.read', 'inventory.write'],
      extra: {
        'GET /api/v1/inventory/orders/o1/availability': (_) => availability(),
        'PUT /api/v1/inventory/order-lines/line1/reservation': (_) => {
          'order_line_id': 'line1',
          'product_id': 'p1',
          'product_code': 'UNIT-1',
          'ordered': '1',
          'consumed': '0',
          'reserved': '1',
          'allocations': [],
        },
        'PUT /api/v1/inventory/order-lines/line2/reservation': (_) => {
          'order_line_id': 'line2',
          'product_id': 'p2',
          'product_code': 'HOSE-25',
          'ordered': '10',
          'consumed': '0',
          'reserved': '0',
          'allocations': [],
        },
      },
    );
    expect(find.text('Stock availability'), findsOneWidget);
    expect(find.text('In stock'), findsOneWidget);
    expect(find.text('Partly in stock'), findsOneWidget);
    // Services and lines without stock are not listed.
    expect(find.textContaining('INSTALL ·'), findsNothing);
    expect(find.textContaining('Short by 6'), findsOneWidget);
    expect(find.text('Reserve'), findsNWidgets(2));
    expect(find.text('Release'), findsOneWidget);

    await tester.tap(find.text('Reserve').first);
    await tester.pumpAndSettle();
    expect(
      (http.bodies['PUT /api/v1/inventory/order-lines/line1/reservation']
          as Map)['quantity'],
      '1',
    );
    await tester.tap(find.text('Release'));
    await tester.pumpAndSettle();
    expect(
      (http.bodies['PUT /api/v1/inventory/order-lines/line2/reservation']
          as Map)['quantity'],
      '0',
    );
  });

  testWidgets(
    'before confirmation availability is shown but nothing can be reserved',
    (tester) async {
      await _screen(
        tester,
        'sent',
        perms: const ['orders.read', 'inventory.read', 'inventory.write'],
        extra: {
          'GET /api/v1/inventory/orders/o1/availability': (_) =>
              availability(reservable: false),
        },
      );
      expect(find.text('Stock availability'), findsOneWidget);
      expect(
        find.textContaining('once the customer has confirmed'),
        findsOneWidget,
      );
      expect(find.text('Reserve'), findsNothing);
    },
  );

  testWidgets(
    'people without inventory.read see no stock panel and trigger no request',
    (tester) async {
      final http = await _screen(tester, 'confirmed');
      expect(find.text('Stock availability'), findsNothing);
      expect(http.requests.where((r) => r.contains('/inventory/')), isEmpty);
    },
  );

  testWidgets('reading inventory does not allow reserving', (tester) async {
    await _screen(
      tester,
      'confirmed',
      perms: const ['orders.read', 'inventory.read'],
      extra: {
        'GET /api/v1/inventory/orders/o1/availability': (_) => availability(),
      },
    );
    expect(find.text('Stock availability'), findsOneWidget);
    expect(find.text('Reserve'), findsNothing);
    expect(find.text('Release'), findsNothing);
  });

  testWidgets(
    'an order line in a unit that does not convert shows the server message',
    (tester) async {
      await _screen(
        tester,
        'confirmed',
        perms: const ['orders.read', 'inventory.read', 'inventory.write'],
        extra: {
          'GET /api/v1/inventory/orders/o1/availability': (_) =>
              const FakeStatus(422, {
                'error': 'validation',
                'message': 'FRAME-A is kept in pcs and has no conversion from set: add how many pcs one set is to the units of the product',
              }),
        },
      );
      expect(find.textContaining('has no conversion from set'), findsOneWidget);
      expect(find.text('Reserve'), findsNothing);
    },
  );

  testWidgets('reserving an order line in an unknown unit shows the refusal', (
    tester,
  ) async {
    await _screen(
      tester,
      'confirmed',
      perms: const ['orders.read', 'inventory.read', 'inventory.write'],
      extra: {
        'GET /api/v1/inventory/orders/o1/availability': (_) => availability(),
        'PUT /api/v1/inventory/order-lines/line1/reservation': (_) =>
            const FakeStatus(422, {
              'error': 'validation',
              'message': 'UNIT-1 is kept in pcs and has no conversion from set',
            }),
      },
    );
    await tester.tap(find.text('Reserve').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('has no conversion from set'), findsOneWidget);
    // Expired stock is called out next to the line.
    expect(find.textContaining('2 expired'), findsOneWidget);
  });
}
