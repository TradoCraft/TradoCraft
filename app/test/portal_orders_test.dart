import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/portal/portal_orders.dart';
import 'package:tradocraft_app/portal/portal_state.dart';

import 'fake_http.dart';

Map<String, Object?> _order({
  String status = 'sent',
  bool canConfirm = true,
  int open = 0,
  int revision = 2,
}) => {
  'id': 'o1',
  'number': 'O2026-00001',
  'revision': revision,
  'status': status,
  'customer_reference': 'PO-77',
  'order_date': '2026-11-06',
  'purpose': 'installation',
  'currency': 'EUR',
  'subtotal': '3686.00',
  'vat_total': '774.06',
  'total': '4460.06',
  'can_confirm': canConfirm,
  'confirmed_at': status == 'confirmed' ? '2026-11-07T09:00:00Z' : null,
  'open_priority_requests': open,
};

Map<String, Object?> _detail(PortalOrderArgs a) => {
  'order': _order(status: a.status, canConfirm: a.canConfirm, open: a.open),
  'lines': [
    {
      'position': 1,
      'product_code': 'UNIT-100',
      'description': 'Process unit 100',
      'unit': 'pcs',
      'quantity': '1',
      'list_unit_price': '3880.0000',
      'net_unit_price': '3686.0000',
      'line_total': '3686.00',
      'vat_rate': '21',
    },
  ],
};

class PortalOrderArgs {
  const PortalOrderArgs({
    this.status = 'sent',
    this.canConfirm = true,
    this.open = 0,
  });
  final String status;
  final bool canConfirm;
  final int open;
}

Future<FakeHttp> _pump(
  WidgetTester tester,
  Widget home, {
  PortalOrderArgs args = const PortalOrderArgs(),
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final http = FakeHttp({
    'GET /api/v1/portal/orders': (_) => [
      _order(status: args.status, canConfirm: args.canConfirm, open: 1),
    ],
    'GET /api/v1/portal/orders/o1': (_) => _detail(args),
    'POST /api/v1/portal/orders/o1/confirm': (_) =>
        _detail(const PortalOrderArgs(status: 'confirmed', canConfirm: false)),
    'POST /api/v1/portal/orders/o1/priority-requests': (_) => {
      'id': 'r1',
      'order_id': 'o1',
      'requested_by_contact_id': 'p1',
      'requested_by_name': 'Sofie Maes',
      'requested_priority': 'expedite',
      'message': 'x',
      'status': 'open',
      'resolution_note': '',
      'created_at': '2026-11-08T09:00:00Z',
      'resolved_at': null,
    },
  });
  final container = ProviderContainer(
    overrides: [
      portalDioProvider.overrideWithValue(fakeDio(http)),
      initialPortalTokenProvider.overrideWithValue('tok'),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, s) =>
            Scaffold(body: PortalOrderPage(id: s.pathParameters['id']!)),
      ),
      GoRoute(path: '/orders', builder: (_, _) => const Text('orders list')),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return http;
}

void main() {
  testWidgets('the order list shows number, revision, status and total', (
    tester,
  ) async {
    await _pump(tester, const PortalOrdersPage());
    expect(find.textContaining('O2026-00001'), findsOneWidget);
    expect(find.textContaining('Revision 2'), findsOneWidget);
    expect(find.text('awaiting your confirmation'), findsOneWidget);
    expect(find.textContaining('€ 4.460,06'), findsOneWidget);
    expect(find.textContaining('1 open priority request'), findsOneWidget);
  });

  testWidgets('Confirm order is enabled when the order can be confirmed', (
    tester,
  ) async {
    final http = await _pump(tester, const PortalOrderPage(id: 'o1'));
    expect(find.text('Process unit 100'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm order').first);
    await tester.pumpAndSettle();
    // The dialog repeats the button label.
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm order').last);
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/portal/orders/o1/confirm'] as Map;
    expect(body['revision'], 2);
    expect(find.text('Thank you, your order is confirmed.'), findsOneWidget);
  });

  testWidgets(
    'Confirm order is disabled with a reason when a newer revision exists',
    (tester) async {
      final http = await _pump(
        tester,
        const PortalOrderPage(id: 'o1'),
        args: const PortalOrderArgs(canConfirm: false),
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm order'),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('newer revision'), findsOneWidget);
      expect(
        http.requests,
        isNot(contains('POST /api/v1/portal/orders/o1/confirm')),
      );
    },
  );

  testWidgets('a confirmed order says so and cannot be confirmed again', (
    tester,
  ) async {
    await _pump(
      tester,
      const PortalOrderPage(id: 'o1'),
      args: const PortalOrderArgs(status: 'confirmed', canConfirm: false),
    );
    expect(find.textContaining('was confirmed on 07/11/2026'), findsOneWidget);
  });

  testWidgets('a priority request needs a message and is posted', (
    tester,
  ) async {
    final http = await _pump(
      tester,
      const PortalOrderPage(id: 'o1'),
      args: const PortalOrderArgs(open: 1),
    );
    expect(find.text('1 open priority request'), findsOneWidget);
    final submit = find.widgetWithText(
      OutlinedButton,
      'Request priority change',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('A reason is required.'), findsOneWidget);
    expect(
      http.requests,
      isNot(contains('POST /api/v1/portal/orders/o1/priority-requests')),
    );

    await tester.enterText(find.byType(TextField), 'Needed for the shutdown');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final body =
        http.bodies['POST /api/v1/portal/orders/o1/priority-requests'] as Map;
    expect(body['priority'], 'expedite');
    expect(body['message'], 'Needed for the shutdown');
    expect(find.text('Your request has been sent.'), findsOneWidget);
  });

  testWidgets('less urgent can be requested too', (tester) async {
    final http = await _pump(tester, const PortalOrderPage(id: 'o1'));
    final low = find.text('Less urgent');
    await tester.ensureVisible(low);
    await tester.tap(low);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Not in a hurry');
    final submit = find.widgetWithText(
      OutlinedButton,
      'Request priority change',
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final body =
        http.bodies['POST /api/v1/portal/orders/o1/priority-requests'] as Map;
    expect(body['priority'], 'low');
  });
}
