import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/detail_routes.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/finance/finance_page.dart';
import 'package:tradocraft_app/features/finance/invoice_screen.dart';
import 'package:tradocraft_app/features/purchasing/order_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _summary({
  String id = 'i1',
  String number = 'F-100',
  String status = 'draft',
  String supplier = 'Acme Motors',
}) => {
  'id': id,
  'company_id': 'co',
  'number': 'SI2027-00001',
  'supplier_id': 's1',
  'supplier_name': supplier,
  'purchase_order_id': 'po1',
  'purchase_order_number': 'PO2027-00001',
  'invoice_number': number,
  'invoice_date': '2027-02-01',
  'due_date': '2027-03-03',
  'currency': 'EUR',
  'status': status,
  'net_total': '100.00',
  'vat_total': '21.00',
  'gross_total': '121.00',
  'notes': '',
  'dispute_reason': '',
  'override_reason': '',
  'payment_reference': '',
  'created_by_user_id': 'u1',
  'created_at': '2027-02-01T00:00:00Z',
  'updated_at': '2027-02-01T00:00:00Z',
};

Map<String, Object?> _line(int n, {String? poLine = 'pl1'}) => {
  'id': 'il$n',
  'invoice_id': 'i1',
  'line_number': n,
  'purchase_order_line_id': poLine,
  'description': 'Motor $n',
  'quantity': '10.0000',
  'unit_price': '10.0000',
  'vat_rate': '21.00',
  'line_net': '100.00',
  'line_vat': '21.00',
  'line_gross': '121.00',
};

Map<String, Object?> _match(
  int n,
  String status, {
  List<String>? issues,
  String? variance,
}) => {
  'invoice_line_id': 'il$n',
  'line_quantity': '10.0000',
  'invoice_unit_price': '10.0000',
  'status': status,
  'issues': issues ?? (status == 'ok' ? <String>[] : [status]),
  'ordered_quantity': '10.0000',
  'received_quantity': '8.0000',
  'invoiced_quantity': '10.0000',
  'po_unit_price': '9.0000',
  'price_variance_pct': variance,
};

Map<String, Object?> _detail({
  String status = 'draft',
  List<String> lineStatuses = const ['ok'],
  bool? matched,
  String override = '',
  String dispute = '',
}) => {
  ..._summary(status: status),
  'override_reason': override,
  'dispute_reason': dispute,
  'lines': [for (var i = 0; i < lineStatuses.length; i++) _line(i + 1)],
  'match_report': {
    'matched': matched ?? lineStatuses.every((s) => s == 'ok'),
    'quantity_tolerance_pct': '0',
    'price_tolerance_pct': '2',
    'lines': [
      for (var i = 0; i < lineStatuses.length; i++)
        _match(
          i + 1,
          lineStatuses[i],
          issues: lineStatuses[i] == 'not_received'
              ? ['not_received', 'price_variance']
              : null,
          variance: '11.1',
        ),
    ],
  },
};

Map<String, Object?> _supplier() => {
  'id': 's1',
  'company_id': 'co',
  'name': 'Acme Motors',
  'code': 'SUP-001',
  'country': 'DE',
  'currency': 'EUR',
  'email': '',
  'phone': '',
  'contact_person': '',
  'payment_terms_days': 30,
  'tax_id': '',
  'active': true,
  'notes': '',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _poSummary(String id, String number, String status) => {
  'id': id,
  'company_id': 'co',
  'number': number,
  'supplier_id': 's1',
  'supplier_name': 'Acme Motors',
  'status': status,
  'order_date': '2027-01-05',
  'currency': 'EUR',
  'subtotal': '125.00',
  'tax_total': '0.00',
  'total': '125.00',
  'notes': '',
  'created_by_user_id': 'u1',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _po(String status) => {
  ..._poSummary('po1', 'PO2027-00001', status),
  'lines': <Object?>[],
};

const _wide = Size(1400, 1600);

Future<void> _app(
  WidgetTester tester,
  FakeHttp http, {
  required String initial,
}) async {
  tester.view.physicalSize = _wide;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/finance',
        builder: (_, _) => const Scaffold(body: FinancePage()),
      ),
      GoRoute(
        path: '/supplier-invoices/:id',
        builder: (_, s) =>
            Scaffold(body: SupplierInvoiceScreen(id: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/purchase-orders/:id',
        builder: (_, s) =>
            Scaffold(body: PurchaseOrderScreen(id: s.pathParameters['id']!)),
      ),
    ],
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

Map<String, Object? Function(Object?)> _routes(
  List<String> perms, {
  Map<String, Object?> Function()? detail,
}) => {
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/suppliers': (_) => [_supplier()],
  'GET /api/v1/supplier-invoices': (_) => {
    'total': 1,
    'items': [_summary()],
  },
  if (detail != null) 'GET /api/v1/supplier-invoices/i1': (_) => detail(),
};

const _read = ['finance.read'];
const _write = ['finance.read', 'finance.write'];
const _all = ['finance.read', 'finance.write', 'finance.approve'];

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('list', () {
    testWidgets('shows invoices with text status, paging and filters', (
      tester,
    ) async {
      final http = FakeHttp({
        ..._routes(_read),
        'GET /api/v1/supplier-invoices': (_) => {
          'total': 60,
          'items': [_summary(), _summary(id: 'i2', number: 'F-101')],
        },
      });
      await _app(tester, http, initial: '/finance');
      expect(find.text('F-100'), findsOneWidget);
      expect(find.byKey(const ValueKey('inv-status-draft')), findsWidgets);
      expect(find.text('draft'), findsWidgets);
      expect(find.text('New supplier invoice'), findsNothing);
      // One visible segment: no segmented control.
      expect(find.byKey(const ValueKey('finance-segments')), findsNothing);
      expect(http.queries.last['limit'], 50);
      expect(http.queries.last['offset'], 0);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(http.queries.last['offset'], 2);

      await tester.tap(find.byKey(const ValueKey('inv-filter-approved')));
      await tester.pumpAndSettle();
      expect(http.queries.last['status'], 'approved');
      expect(http.queries.last['offset'], 0);

      await tester.tap(find.byKey(const ValueKey('inv-filter-supplier')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Motors').last);
      await tester.pumpAndSettle();
      expect(http.queries.last['supplier_id'], 's1');
      expect(http.queries.last['status'], 'approved');

      await tester.enterText(find.byType(TextField).first, 'F-10');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(http.queries.last['q'], 'F-10');
    });

    testWidgets('empty and error states', (tester) async {
      final empty = FakeHttp({
        ..._routes(_read),
        'GET /api/v1/supplier-invoices': (_) => {
          'total': 0,
          'items': <Object?>[],
        },
      });
      await _app(tester, empty, initial: '/finance');
      expect(find.text('No supplier invoices found.'), findsOneWidget);

      final failing = FakeHttp({
        ..._routes(_read),
        'GET /api/v1/supplier-invoices': (_) =>
            const FakeStatus(500, {'error': 'x', 'message': 'Database down'}),
      });
      await _app(tester, failing, initial: '/finance');
      expect(find.text('Database down'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('segments: settings only with finance.approve', (tester) async {
      await _app(tester, FakeHttp(_routes(_write)), initial: '/finance');
      expect(find.byKey(const ValueKey('finance-segments')), findsNothing);

      await _app(tester, FakeHttp(_routes(_all)), initial: '/finance');
      expect(find.byKey(const ValueKey('finance-segments')), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('create', () {
    Map<String, Object? Function(Object?)> createRoutes() => {
      ..._routes(_write),
      'GET /api/v1/purchase-orders': (_) => [
        _poSummary('po1', 'PO2027-00001', 'received'),
      ],
      'POST /api/v1/supplier-invoices': (_) => _detail(),
      'GET /api/v1/supplier-invoices/i1': (_) => _detail(),
    };

    Future<void> openDialog(WidgetTester tester, FakeHttp http) async {
      await _app(tester, http, initial: '/finance');
      await tester.tap(find.text('New supplier invoice'));
      await tester.pumpAndSettle();
    }

    Future<void> pickSupplier(WidgetTester tester) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('inv-supplier')),
          matching: find.byType(TextField),
        ),
        'acme',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('SUP-001 · Acme Motors').last);
      await tester.pumpAndSettle();
    }

    testWidgets('creates free-text lines without an order', (tester) async {
      final http = FakeHttp(createRoutes());
      await openDialog(tester, http);
      await pickSupplier(tester);
      await tester.enterText(find.byKey(const ValueKey('inv-number')), 'F-9');
      await tester.enterText(
        find.byKey(const ValueKey('inv-line-desc-0')),
        'Freight',
      );
      await tester.enterText(find.byKey(const ValueKey('inv-line-qty-0')), '2');
      await tester.enterText(
        find.byKey(const ValueKey('inv-line-price-0')),
        '12,5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('inv-line-vat-0')),
        '21',
      );
      await tester.tap(find.byKey(const ValueKey('inv-save')));
      await tester.pumpAndSettle();
      final body =
          http.bodies['POST /api/v1/supplier-invoices']!
              as Map<String, Object?>;
      expect(body['supplier_id'], 's1');
      expect(body['purchase_order_id'], isNull);
      expect(body['invoice_number'], 'F-9');
      final line = (body['lines']! as List).single as Map;
      expect(line['description'], 'Freight');
      expect(line['unit_price'], '12.5');
      expect(line['vat_rate'], '21');
      // The new invoice opened.
      expect(find.byKey(const ValueKey('inv-approve')), findsNothing);
      expect(find.text('F-100'), findsWidgets);
      expect(http.requests, contains('GET /api/v1/supplier-invoices/i1'));
    });

    testWidgets('with an order and no lines the backend prefills', (
      tester,
    ) async {
      final http = FakeHttp(createRoutes());
      await openDialog(tester, http);
      await pickSupplier(tester);
      await tester.tap(find.byKey(const ValueKey('inv-order')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PO2027-00001').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inv-prefill-hint')), findsOneWidget);
      expect(find.byKey(const ValueKey('inv-line-desc-0')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('inv-number')), 'F-9');
      await tester.tap(find.byKey(const ValueKey('inv-save')));
      await tester.pumpAndSettle();
      final body =
          http.bodies['POST /api/v1/supplier-invoices']!
              as Map<String, Object?>;
      expect(body['purchase_order_id'], 'po1');
      expect(body.containsKey('lines'), isFalse);
      // Only orders that have receipts are offered.
      final statuses = [
        for (var i = 0; i < http.requests.length; i++)
          if (http.requests[i] == 'GET /api/v1/purchase-orders')
            http.queries[i]['status'],
      ];
      expect(statuses, ['partially_received', 'received']);
    });

    testWidgets('validates like the backend', (tester) async {
      final http = FakeHttp(createRoutes());
      await openDialog(tester, http);
      await tester.tap(find.byKey(const ValueKey('inv-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('The invoice number is required (at most 64 characters).'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const ValueKey('inv-number')), 'F-9');
      await tester.tap(find.byKey(const ValueKey('inv-save')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a supplier.'), findsOneWidget);
      await pickSupplier(tester);
      await tester.tap(find.byKey(const ValueKey('inv-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('A free-text line needs a description.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('inv-line-desc-0')),
        'Freight',
      );
      await tester.enterText(find.byKey(const ValueKey('inv-line-qty-0')), '0');
      await tester.tap(find.byKey(const ValueKey('inv-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Quantity must be greater'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('inv-line-qty-0')), '1');
      await tester.enterText(
        find.byKey(const ValueKey('inv-line-price-0')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('inv-line-vat-0')),
        '120',
      );
      await tester.tap(find.byKey(const ValueKey('inv-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('VAT rate must be between'), findsOneWidget);
      expect(http.requests, isNot(contains('POST /api/v1/supplier-invoices')));
    });

    testWidgets('shows a duplicate number (409) in the dialog', (tester) async {
      final http = FakeHttp({
        ...createRoutes(),
        'POST /api/v1/supplier-invoices': (_) => const FakeStatus(409, {
          'error': 'conflict',
          'message': 'invoice number F-9 already exists for this supplier',
        }),
      });
      await openDialog(tester, http);
      await pickSupplier(tester);
      await tester.enterText(find.byKey(const ValueKey('inv-number')), 'F-9');
      await tester.enterText(
        find.byKey(const ValueKey('inv-line-desc-0')),
        'Freight',
      );
      await tester.enterText(find.byKey(const ValueKey('inv-line-qty-0')), '1');
      await tester.enterText(
        find.byKey(const ValueKey('inv-line-price-0')),
        '1',
      );
      await tester.tap(find.byKey(const ValueKey('inv-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('invoice number F-9 already exists for this supplier'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('inv-save')), findsOneWidget);
    });
  });

  group('detail', () {
    Future<FakeHttp> open(
      WidgetTester tester,
      List<String> perms,
      Map<String, Object?> Function() detail, {
      Map<String, Object? Function(Object?)> extra = const {},
    }) async {
      final http = FakeHttp({..._routes(perms, detail: detail), ...extra});
      await _app(tester, http, initial: '/supplier-invoices/i1');
      return http;
    }

    testWidgets('renders every line status with its numbers and issues', (
      tester,
    ) async {
      await open(
        tester,
        _read,
        () => _detail(
          lineStatuses: [
            'ok',
            'not_received',
            'over_invoiced',
            'price_variance',
            'no_po_line',
          ],
        ),
      );
      expect(find.text('F-100'), findsOneWidget);
      expect(find.text('Acme Motors'), findsOneWidget);
      expect(find.byKey(const ValueKey('inv-open-po')), findsOneWidget);
      for (final (n, text) in [
        (1, 'ok'),
        (2, 'not received'),
        (3, 'over invoiced'),
        (4, 'price variance'),
        (5, 'no order line'),
      ]) {
        final chip = find.byKey(ValueKey('inv-match-$n'));
        await tester.ensureVisible(chip);
        expect(
          find.descendant(of: chip, matching: find.text(text)),
          findsOneWidget,
          reason: 'line $n',
        );
      }
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('inv-match-numbers-2')))
            .data,
        allOf(
          contains('Ordered: 10'),
          contains('Received: 8'),
          contains('Invoiced: 10'),
          contains('Order price: € 9,00'),
          contains('Invoice price: € 10,00'),
          contains('Variance: 11,1 %'),
        ),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('inv-match-issues-2')))
            .data,
        'not received, price variance',
      );
      expect(
        find.text('The invoice does not match the order and the receipts.'),
        findsOneWidget,
      );
    });

    testWidgets('a clean match shows the matches banner', (tester) async {
      await open(tester, _read, () => _detail(status: 'matched'));
      expect(
        find.text('The invoice matches the order and the receipts.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('inv-status-matched')), findsOneWidget);
    });

    testWidgets('actions per status and permission', (tester) async {
      Future<void> check(
        List<String> perms,
        String status,
        Set<String> expected,
      ) async {
        await open(tester, perms, () => _detail(status: status));
        const all = [
          'inv-edit',
          'inv-submit-match',
          'inv-approve',
          'inv-mark-paid',
          'inv-dispute',
          'inv-reopen',
          'inv-delete',
        ];
        final shown = {
          for (final k in all)
            if (find.byKey(ValueKey(k)).evaluate().isNotEmpty) k,
        };
        expect(shown, expected, reason: '$status with $perms');
      }

      await check(_all, 'draft', {
        'inv-edit',
        'inv-submit-match',
        'inv-approve',
        'inv-dispute',
        'inv-delete',
      });
      await check(_write, 'draft', {
        'inv-edit',
        'inv-submit-match',
        'inv-dispute',
        'inv-delete',
      });
      await check(_read, 'draft', {});
      await check(_all, 'matched', {
        'inv-submit-match',
        'inv-approve',
        'inv-dispute',
        'inv-reopen',
      });
      await check(_all, 'approved', {'inv-mark-paid', 'inv-dispute'});
      await check(_write, 'approved', {'inv-dispute'});
      await check(_all, 'disputed', {'inv-reopen'});
      await check(_all, 'paid', {});
    });

    testWidgets('submit match, then approve a clean match without a reason', (
      tester,
    ) async {
      final http = await open(
        tester,
        _all,
        () => _detail(),
        extra: {
          'POST /api/v1/supplier-invoices/i1/submit-match': (_) =>
              _detail(status: 'matched'),
          'POST /api/v1/supplier-invoices/i1/approve': (_) =>
              _detail(status: 'approved'),
        },
      );
      await _tapKey(tester, 'inv-submit-match');
      expect(find.byKey(const ValueKey('inv-status-matched')), findsOneWidget);
      await _tapKey(tester, 'inv-approve');
      expect(find.byKey(const ValueKey('inv-reason')), findsNothing);
      expect(find.byKey(const ValueKey('inv-status-approved')), findsOneWidget);
      final body =
          http.bodies['POST /api/v1/supplier-invoices/i1/approve'] as Map?;
      expect(body?['override_reason'], isNull);
    });

    testWidgets('approving a mismatch asks for an override reason', (
      tester,
    ) async {
      final http = await open(
        tester,
        _all,
        () => _detail(lineStatuses: ['price_variance']),
        extra: {
          'POST /api/v1/supplier-invoices/i1/approve': (_) =>
              _detail(status: 'approved', override: 'Agreed by phone'),
        },
      );
      await _tapKey(tester, 'inv-approve');
      expect(find.byKey(const ValueKey('inv-reason')), findsOneWidget);
      await _tapKey(tester, 'inv-reason-ok');
      expect(find.text('A reason is required.'), findsOneWidget);
      expect(
        http.requests,
        isNot(contains('POST /api/v1/supplier-invoices/i1/approve')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('inv-reason')),
        'Agreed by phone',
      );
      await _tapKey(tester, 'inv-reason-ok');
      expect(
        (http.bodies['POST /api/v1/supplier-invoices/i1/approve']!
            as Map)['override_reason'],
        'Agreed by phone',
      );
      expect(find.text('Agreed by phone'), findsOneWidget);
    });

    testWidgets('dispute needs a reason; reopen returns to draft', (
      tester,
    ) async {
      final http = await open(
        tester,
        _write,
        () => _detail(status: 'matched'),
        extra: {
          'POST /api/v1/supplier-invoices/i1/dispute': (_) =>
              _detail(status: 'disputed', dispute: 'Wrong price'),
          'POST /api/v1/supplier-invoices/i1/reopen': (_) => _detail(),
        },
      );
      await _tapKey(tester, 'inv-dispute');
      await _tapKey(tester, 'inv-reason-ok');
      expect(find.text('A reason is required.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('inv-reason')),
        'Wrong price',
      );
      await _tapKey(tester, 'inv-reason-ok');
      expect(
        (http.bodies['POST /api/v1/supplier-invoices/i1/dispute']!
            as Map)['reason'],
        'Wrong price',
      );
      expect(find.byKey(const ValueKey('inv-status-disputed')), findsOneWidget);
      expect(find.text('Wrong price'), findsOneWidget);
      await _tapKey(tester, 'inv-reopen');
      expect(find.byKey(const ValueKey('inv-status-draft')), findsOneWidget);
    });

    testWidgets('mark paid sends date and reference', (tester) async {
      final http = await open(
        tester,
        _all,
        () => _detail(status: 'approved'),
        extra: {
          'POST /api/v1/supplier-invoices/i1/mark-paid': (_) =>
              _detail(status: 'paid'),
        },
      );
      await _tapKey(tester, 'inv-mark-paid');
      await tester.enterText(
        find.byKey(const ValueKey('inv-payment-reference')),
        'BANK-77',
      );
      await _tapKey(tester, 'inv-paid-ok');
      final body =
          http.bodies['POST /api/v1/supplier-invoices/i1/mark-paid']! as Map;
      expect(body['payment_reference'], 'BANK-77');
      expect(body['paid_at'], isNotNull);
      expect(find.byKey(const ValueKey('inv-status-paid')), findsOneWidget);
    });

    testWidgets('lifecycle conflicts show in the banner', (tester) async {
      await open(
        tester,
        _all,
        () => _detail(),
        extra: {
          'POST /api/v1/supplier-invoices/i1/submit-match': (_) =>
              const FakeStatus(409, {
                'error': 'conflict',
                'message': 'invoice is approved',
              }),
        },
      );
      await _tapKey(tester, 'inv-submit-match');
      expect(find.byKey(const ValueKey('inv-banner')), findsOneWidget);
      expect(find.text('invoice is approved'), findsOneWidget);
    });

    testWidgets('a draft is edited and deleted after confirmation', (
      tester,
    ) async {
      final http = await open(
        tester,
        _write,
        () => _detail(),
        extra: {
          'PUT /api/v1/supplier-invoices/i1': (_) => _detail(),
          'DELETE /api/v1/supplier-invoices/i1': (_) => null,
        },
      );
      await _tapKey(tester, 'inv-edit');
      await tester.enterText(find.byKey(const ValueKey('inv-line-qty-0')), '5');
      await _tapKey(tester, 'inv-edit-save');
      final body = http.bodies['PUT /api/v1/supplier-invoices/i1']! as Map;
      final line = (body['lines']! as List).single as Map;
      expect(line['quantity'], '5');
      // The order line link is kept.
      expect(line['purchase_order_line_id'], 'pl1');
      expect(find.byKey(const ValueKey('inv-edit-save')), findsNothing);

      await _tapKey(tester, 'inv-delete');
      expect(find.textContaining('Delete invoice F-100?'), findsOneWidget);
      await _tapKey(tester, 'inv-delete-confirm');
      expect(http.requests, contains('DELETE /api/v1/supplier-invoices/i1'));
    });
  });

  group('settings', () {
    Map<String, Object? Function(Object?)> routes() => {
      ..._routes(_all),
      'GET /api/v1/finance/settings': (_) => {
        'quantity_tolerance_pct': '0',
        'price_tolerance_pct': '2',
      },
      'PUT /api/v1/finance/settings': (b) => {
        'quantity_tolerance_pct': (b! as Map)['quantity_tolerance_pct'],
        'price_tolerance_pct': (b as Map)['price_tolerance_pct'],
      },
    };

    testWidgets('edits and saves the tolerances', (tester) async {
      final http = FakeHttp(routes());
      await _app(tester, http, initial: '/finance');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fin-price-tolerance')),
        '3,5',
      );
      await tester.tap(find.byKey(const ValueKey('fin-settings-save')));
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/finance/settings']! as Map;
      expect(body['price_tolerance_pct'], '3.5');
      expect(body['quantity_tolerance_pct'], '0');
      expect(find.text('Settings saved.'), findsOneWidget);
    });

    testWidgets('rejects an out-of-range percentage', (tester) async {
      final http = FakeHttp(routes());
      await _app(tester, http, initial: '/finance');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fin-qty-tolerance')),
        '101',
      );
      await tester.tap(find.byKey(const ValueKey('fin-settings-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a percentage between 0 and 100.'),
        findsOneWidget,
      );
      expect(http.requests, isNot(contains('PUT /api/v1/finance/settings')));
    });
  });

  group('navigation', () {
    Future<void> shell(WidgetTester tester, List<String> perms) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final http = FakeHttp(_routes(perms));
      final router = GoRouter(
        initialLocation: perms.contains('finance.read')
            ? '/finance'
            : '/orders',
        routes: [
          ShellRoute(
            builder: (c, s, child) =>
                AppShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(path: '/finance', builder: (_, _) => const FinancePage()),
              GoRoute(
                path: '/orders',
                builder: (_, _) => const Text('ORDERS LIST'),
              ),
            ],
          ),
        ],
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

    testWidgets('Finance is shown with finance.read', (tester) async {
      await shell(tester, ['finance.read', 'orders.read']);
      expect(find.text('Finance'), findsWidgets);
      expect(find.text('F-100'), findsOneWidget);
    });

    testWidgets('Finance is hidden without finance.read', (tester) async {
      await shell(tester, ['orders.read']);
      expect(find.text('Finance'), findsNothing);
      expect(find.text('ORDERS LIST'), findsOneWidget);
    });
  });

  test('a supplier invoice is a detail location with a tab label', () {
    expect(isDetailLocation('/supplier-invoices/abcdef123456'), isTrue);
    expect(isDetailLocation('/supplier-invoices'), isFalse);
    expect(sectionOfDetail('/supplier-invoices/x'), '/finance');
    final l = lookupAppLocalizations(const Locale('en'));
    expect(
      tabLabel(
        l,
        const WorkTab(id: 1, location: '/supplier-invoices/abcdef123456'),
      ),
      'Supplier invoice abcdef12',
    );
    expect(
      tabLabel(
        l,
        const WorkTab(id: 1, location: '/supplier-invoices/i1', title: 'F-100'),
      ),
      'F-100',
    );
  });

  group('purchase order shortcut', () {
    Future<void> openOrder(
      WidgetTester tester,
      List<String> perms,
      String status,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(perms),
        'GET /api/v1/purchase-orders/po1': (_) => _po(status),
        'GET /api/v1/purchase-orders/po1/receipts': (_) => <Object?>[],
        'GET /api/v1/purchase-orders': (_) => <Object?>[],
        'POST /api/v1/supplier-invoices': (_) => _detail(),
        'GET /api/v1/supplier-invoices/i1': (_) => _detail(),
      });
      await _app(tester, http, initial: '/purchase-orders/po1');
    }

    testWidgets('is shown for received orders with finance.write', (
      tester,
    ) async {
      await openOrder(tester, ['purchasing.read', 'finance.write'], 'received');
      expect(find.byKey(const ValueKey('po-create-invoice')), findsOneWidget);
      await _tapKey(tester, 'po-create-invoice');
      expect(find.byKey(const ValueKey('inv-supplier-fixed')), findsOneWidget);
      expect(find.byKey(const ValueKey('inv-prefill-hint')), findsOneWidget);
    });

    testWidgets('is hidden without finance.write or for other statuses', (
      tester,
    ) async {
      await openOrder(tester, ['purchasing.read'], 'received');
      expect(find.byKey(const ValueKey('po-create-invoice')), findsNothing);
      await openOrder(tester, ['purchasing.read', 'finance.write'], 'approved');
      expect(find.byKey(const ValueKey('po-create-invoice')), findsNothing);
      await openOrder(tester, [
        'purchasing.read',
        'finance.write',
      ], 'partially_received');
      expect(find.byKey(const ValueKey('po-create-invoice')), findsOneWidget);
    });
  });
}
