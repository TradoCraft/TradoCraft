import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/mrp/mrp_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _proposal(
  String id,
  String kind,
  String code, {
  String quantity = '10.0000',
  String? supplier,
  bool late = false,
  String reason = 'demand',
  String status = 'open',
  String? convertedTo,
  List<Map<String, Object?>> pegging = const [
    {
      'kind': 'sales_order',
      'id': null,
      'number': 'SO2027-00001',
      'quantity': '2.0000',
    },
  ],
}) => {
  'id': id,
  'run_id': 'r1',
  'run_number': 'MRP2027-00002',
  'product_id': 'prod-$code',
  'product_code': code,
  'product_name': 'Name of $code',
  'kind': kind,
  'quantity': quantity,
  'need_date': '2027-03-10',
  'order_date': '2027-03-05',
  'late': late,
  'supplier_id': supplier == null ? null : 's1',
  'supplier_name': supplier,
  'reason': reason,
  'pegging': pegging,
  'status': status,
  'converted_to': convertedTo,
  'converted_at': null,
};

final _run = {
  'id': 'r1',
  'number': 'MRP2027-00002',
  'planned_on': '2027-03-01',
  'horizon_days': 90,
  'proposals': 3,
  'created_at': '2027-03-01T08:00:00Z',
};

/// A server for the page. `proposals` is what `GET /mrp/proposals` answers.
FakeHttp _server({
  List<String> permissions = const [
    'production.read',
    'production.write',
    'purchasing.read',
    'purchasing.write',
  ],
  List<Map<String, Object?>>? proposals,
}) {
  final list =
      proposals ??
      [
        _proposal('a', 'production', 'FRAME-A', quantity: '2.0000'),
        _proposal(
          'b',
          'purchase',
          'PROFILE-40',
          quantity: '14.3000',
          supplier: 'Steel NV',
          late: true,
        ),
        _proposal(
          'c',
          'purchase',
          'BOLT-M8',
          reason: 'safety_stock',
          pegging: const [],
        ),
      ];
  return FakeHttp({
    'GET /api/v1/me': (_) => meJson(permissions),
    'GET /api/v1/mrp/proposals': (_) => list,
    'GET /api/v1/mrp/runs': (_) => [_run],
    'POST /api/v1/mrp/runs': (_) => _run,
    'POST /api/v1/mrp/proposals/b/convert': (_) => {
      'proposal': _proposal(
        'b',
        'purchase',
        'PROFILE-40',
        status: 'converted',
        convertedTo: 'po1',
      ),
      'converted_to': 'po1',
      'number': 'PO2027-00007',
    },
    'POST /api/v1/mrp/proposals/c/convert': (_) => {
      'proposal': _proposal(
        'c',
        'purchase',
        'BOLT-M8',
        status: 'converted',
        convertedTo: 'po2',
      ),
      'converted_to': 'po2',
      'number': 'PO2027-00008',
    },
    'POST /api/v1/mrp/proposals/a/convert': (_) => {
      'proposal': _proposal(
        'a',
        'production',
        'FRAME-A',
        status: 'converted',
        convertedTo: 'mo1',
      ),
      'converted_to': 'mo1',
      'number': 'PRO2027-00001',
    },
    'POST /api/v1/mrp/proposals/a/dismiss': (_) =>
        _proposal('a', 'production', 'FRAME-A', status: 'dismissed'),
    'GET /api/v1/suppliers': (_) => [
      {
        'id': 's9',
        'company_id': 'c1',
        'name': 'Other Supplier',
        'code': 'OTH',
        'country': 'be',
        'currency': 'EUR',
        'email': '',
        'phone': '',
        'contact_person': '',
        'tax_id': '',
        'notes': '',
        'payment_terms_days': 30,
        'active': true,
        'created_at': '2027-01-01T00:00:00Z',
        'updated_at': '2027-01-01T00:00:00Z',
      },
    ],
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const MrpPage()),
      GoRoute(
        path: '/purchase-orders/:id',
        builder: (_, s) => Text('purchase order ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/production/:id',
        builder: (_, s) => Text('production order ${s.pathParameters['id']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the proposals with what they are for', (tester) async {
    final http = _server();
    await _pump(tester, http);
    expect(find.text('FRAME-A · Name of FRAME-A'), findsOneWidget);
    expect(find.text('PROFILE-40 · Name of PROFILE-40'), findsOneWidget);
    expect(find.byKey(const ValueKey('mrp-qty-b')), findsOneWidget);
    expect(find.text('14.3000'), findsOneWidget);
    expect(find.text('Steel NV'), findsOneWidget);
    // What a proposal serves, the safety stock, and the late flag.
    expect(find.textContaining('Order SO2027-00001'), findsNWidgets(2));
    expect(find.text('Safety stock'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Order by Fri 5 Mar'), findsNWidgets(3));
    expect(find.text('Needed Wed 10 Mar'), findsNWidgets(3));
    // The latest run, and the open proposals were asked for.
    expect(find.text('Last run: MRP2027-00002'), findsOneWidget);
    expect(
      http.queries.firstWhere((q) => q.containsKey('status'))['status'],
      'open',
    );
  });

  testWidgets('says so when there is nothing to buy or build', (tester) async {
    await _pump(tester, _server(proposals: const []));
    expect(find.text('Nothing to buy or build.'), findsOneWidget);
  });

  testWidgets('runs the planning for the chosen horizon and reloads', (
    tester,
  ) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.text('180 days'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mrp-run')));
    await tester.pumpAndSettle();
    expect(http.bodies['POST /api/v1/mrp/runs'], {'horizon_days': 180});
    expect(find.text('Planning done: 3 proposals.'), findsOneWidget);
    expect(
      http.requests.where((r) => r == 'GET /api/v1/mrp/proposals').length,
      2,
    );
  });

  testWidgets('turns a proposal into an order and reloads', (tester) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('mrp-convert-b')));
    await tester.pumpAndSettle();
    // It has a supplier, so nothing is asked.
    expect(find.text('Choose a supplier'), findsNothing);
    final body = http.bodies['POST /api/v1/mrp/proposals/b/convert'] as Map;
    expect(body['supplier_id'], isNull);
    expect(find.text('Order PO2027-00007 created.'), findsOneWidget);
    expect(
      http.requests.where((r) => r == 'GET /api/v1/mrp/proposals').length,
      2,
    );
    // A production proposal needs no supplier either.
    await tester.tap(find.byKey(const ValueKey('mrp-convert-a')));
    await tester.pumpAndSettle();
    expect(
      http.requests.contains('POST /api/v1/mrp/proposals/a/convert'),
      true,
    );
  });

  testWidgets('a purchase without a supplier asks for one first', (
    tester,
  ) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('mrp-convert-c')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a supplier'), findsOneWidget);
    // Nothing happens until one is chosen.
    expect(
      http.requests.contains('POST /api/v1/mrp/proposals/c/convert'),
      false,
    );
    await tester.tap(find.byKey(const ValueKey('mrp-supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Supplier').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create order').last);
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/mrp/proposals/c/convert'] as Map;
    expect(body['supplier_id'], 's9');
    expect(find.text('Order PO2027-00008 created.'), findsOneWidget);
  });

  testWidgets('cancelling the supplier choice orders nothing', (tester) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('mrp-convert-c')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      http.requests.contains('POST /api/v1/mrp/proposals/c/convert'),
      false,
    );
  });

  testWidgets('dismisses a proposal', (tester) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('mrp-dismiss-a')));
    await tester.pumpAndSettle();
    expect(
      http.requests.contains('POST /api/v1/mrp/proposals/a/dismiss'),
      true,
    );
    expect(find.text('Proposal dismissed.'), findsOneWidget);
  });

  testWidgets('what one may do follows the permissions', (tester) async {
    // A buyer: sees the proposals, acts on purchases only, does not run the planning.
    final buyer = _server(
      permissions: const ['purchasing.read', 'purchasing.write'],
    );
    await _pump(tester, buyer);
    expect(find.byKey(const ValueKey('mrp-run')), findsNothing);
    expect(find.byKey(const ValueKey('mrp-horizon')), findsNothing);
    expect(find.byKey(const ValueKey('mrp-convert-b')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mrp-convert-a')),
      findsNothing,
      reason: 'a build is not theirs',
    );
    // A reader sees, and acts on nothing.
    final reader = _server(
      permissions: const ['production.read', 'purchasing.read'],
    );
    await _pump(tester, reader);
    expect(find.byKey(const ValueKey('mrp-run')), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byKey(const ValueKey('mrp-dismiss-a')), findsNothing);
  });

  testWidgets('the status and kind filters ask for what they say', (
    tester,
  ) async {
    final http = _server();
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('mrp-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismissed').last);
    await tester.pumpAndSettle();
    expect(
      http.queries.where((q) => q.containsKey('status')).last['status'],
      'dismissed',
    );
    await tester.tap(find.byKey(const ValueKey('mrp-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy').last);
    await tester.pumpAndSettle();
    final last = http.queries.where((q) => q.containsKey('status')).last;
    expect(last['kind'], 'purchase');
    expect(last['status'], 'dismissed');
  });

  testWidgets('a converted proposal opens its order', (tester) async {
    final http = _server(
      proposals: [
        _proposal(
          'p',
          'purchase',
          'PROFILE-40',
          status: 'converted',
          convertedTo: 'po1',
        ),
        _proposal(
          'q',
          'production',
          'FRAME-A',
          status: 'converted',
          convertedTo: 'mo1',
        ),
      ],
    );
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('mrp-q')));
    await tester.pumpAndSettle();
    expect(find.text('production order mo1'), findsOneWidget);
  });
}
