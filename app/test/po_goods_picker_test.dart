import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/purchasing/po_form.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _supplier(String id, String code, String name) => {
  'id': id,
  'company_id': 'co',
  'name': name,
  'code': code,
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

Map<String, Object?> _entry(
  String supplier,
  String product,
  String code,
  String name, {
  String moq = '1.0000',
  String sku = '',
  String price = '10.0000',
}) => {
  'id': 'sp-$supplier-$product',
  'company_id': 'co',
  'supplier_id': supplier,
  'supplier_name': 'S',
  'product_id': product,
  'product_code': code,
  'product_name': name,
  'supplier_product_code': sku,
  'supplier_product_name': '',
  'currency': 'EUR',
  'unit_price': price,
  'moq': moq,
  'lead_time_days': 0,
  'is_preferred': false,
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

Map<String, Object?> _po() => {
  'id': 'po9',
  'company_id': 'co',
  'number': 'PO-9',
  'supplier_id': 's1',
  'supplier_name': 'Acme',
  'status': 'draft',
  'order_date': '2027-01-05',
  'currency': 'EUR',
  'subtotal': '0',
  'tax_total': '0',
  'total': '0',
  'notes': '',
  'created_by_user_id': 'u1',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
  'lines': <Object?>[],
};

FakeHttp _http({List<Object?>? s1, List<Object?>? s2}) => FakeHttp({
  'GET /api/v1/suppliers': (_) => [
    _supplier('s1', 'SUP-1', 'Acme'),
    _supplier('s2', 'SUP-2', 'Bolt'),
    _supplier('s3', 'SUP-3', 'Empty'),
  ],
  'GET /api/v1/suppliers/s1/products': (_) =>
      s1 ??
      [
        _entry('s1', 'p1', 'MOT-1', 'Motor', moq: '5.0000', sku: 'AC-1'),
        _entry('s1', 'p2', 'FRM-1', 'Frame', price: '4.5000'),
        _entry('s1', 'p3', 'CTL-1', 'Controller', moq: '2.5000'),
      ],
  'GET /api/v1/suppliers/s2/products': (_) =>
      s2 ?? [_entry('s2', 'p9', 'BLT-1', 'Bolt')],
  'GET /api/v1/suppliers/s3/products': (_) => <Object?>[],
  'POST /api/v1/purchase-orders': (_) => _po(),
});

Future<void> _open(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1400, 1800);
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
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showNewPurchaseOrderDialog(c),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _supplierPick(WidgetTester tester, String q, String label) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('po-supplier')),
      matching: find.byType(TextField),
    ),
    q,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

String _qty(WidgetTester tester, String id) => tester
    .widget<TextField>(find.byKey(ValueKey('po-goods-qty-$id')))
    .controller!
    .text;

bool _checked(WidgetTester tester, String id) =>
    tester.widget<Checkbox>(find.byKey(ValueKey('po-goods-check-$id'))).value!;

void main() {
  testWidgets('lists the supplier goods with code first and the details', (
    tester,
  ) async {
    await _open(tester, _http());
    expect(
      find.byKey(const ValueKey('po-goods-pick-supplier')),
      findsOneWidget,
    );
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    expect(find.text('MOT-1 · Motor'), findsOneWidget);
    expect(find.text('FRM-1 · Frame'), findsOneWidget);
    expect(find.textContaining('AC-1 · € 10,00 · MOQ 5'), findsOneWidget);
    expect(find.textContaining('€ 4,50 · MOQ 1'), findsOneWidget);
    expect(_checked(tester, 'p1'), isFalse);
  });

  testWidgets('ticking pre-fills the minimum order quantity, else 1', (
    tester,
  ) async {
    await _open(tester, _http());
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    await tester.tap(find.byKey(const ValueKey('po-goods-check-p1')));
    await tester.pumpAndSettle();
    expect(_qty(tester, 'p1'), '5');
    expect(_checked(tester, 'p1'), isTrue);
    await tester.tap(find.byKey(const ValueKey('po-goods-check-p3')));
    await tester.pumpAndSettle();
    expect(_qty(tester, 'p3'), '2.5');
    expect(find.textContaining('1 lines'), findsNothing);
    expect(find.textContaining('2 lines, total'), findsOneWidget);
  });

  testWidgets('a supplier product without a usable minimum gets 1', (
    tester,
  ) async {
    final http = _http(s1: [_entry('s1', 'p1', 'MOT-1', 'Motor', moq: '0')]);
    await _open(tester, http);
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    await tester.tap(find.byKey(const ValueKey('po-goods-check-p1')));
    await tester.pumpAndSettle();
    expect(_qty(tester, 'p1'), '1');
  });

  testWidgets(
    'typing a quantity ticks the box, clearing or unticking removes it',
    (tester) async {
      await _open(tester, _http());
      await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
      await tester.enterText(
        find.byKey(const ValueKey('po-goods-qty-p2')),
        '7',
      );
      await tester.pumpAndSettle();
      expect(_checked(tester, 'p2'), isTrue);

      await tester.enterText(find.byKey(const ValueKey('po-goods-qty-p2')), '');
      await tester.pumpAndSettle();
      expect(_checked(tester, 'p2'), isFalse);

      await tester.tap(find.byKey(const ValueKey('po-goods-check-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('po-goods-check-p1')));
      await tester.pumpAndSettle();
      expect(_checked(tester, 'p1'), isFalse);
      expect(_qty(tester, 'p1'), '');

      await tester.tap(find.byKey(const ValueKey('po-save')));
      await tester.pumpAndSettle();
      expect(find.text('Add at least one line.'), findsOneWidget);
    },
  );

  testWidgets('a quantity below the minimum is flagged but allowed', (
    tester,
  ) async {
    await _open(tester, _http());
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    await tester.enterText(find.byKey(const ValueKey('po-goods-qty-p1')), '3');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('po-goods-moq-warning-p1')),
      findsOneWidget,
    );
    expect(find.text('Below the minimum order quantity (5)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('po-goods-qty-p1')), '5');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('po-goods-moq-warning-p1')), findsNothing);
  });

  testWidgets('the filter narrows the list', (tester) async {
    await _open(tester, _http());
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    await tester.enterText(
      find.byKey(const ValueKey('po-goods-filter')),
      'ctl',
    );
    await tester.pumpAndSettle();
    expect(find.text('CTL-1 · Controller'), findsOneWidget);
    expect(find.text('MOT-1 · Motor'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('po-goods-filter')),
      'zzz',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('po-goods-nomatch')), findsOneWidget);
  });

  testWidgets('a supplier without products shows the empty state', (
    tester,
  ) async {
    await _open(tester, _http());
    await _supplierPick(tester, 'empty', 'SUP-3 · Empty');
    expect(find.byKey(const ValueKey('po-goods-empty')), findsOneWidget);
    expect(find.textContaining('price list first'), findsOneWidget);
  });

  testWidgets('a long list scrolls inside a bounded area', (tester) async {
    final many = [
      for (var i = 0; i < 60; i++) _entry('s1', 'p$i', 'C-$i', 'Item $i'),
    ];
    await _open(tester, _http(s1: many));
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    expect(find.text('C-0 · Item 0'), findsOneWidget);
    expect(find.text('C-59 · Item 59'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.text('C-59 · Item 59'), findsOneWidget);
  });

  testWidgets('saving submits the chosen goods with price list values', (
    tester,
  ) async {
    final http = _http();
    await _open(tester, http);
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    await tester.tap(find.byKey(const ValueKey('po-goods-check-p1')));
    await tester.enterText(find.byKey(const ValueKey('po-goods-qty-p2')), '30');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('po-save')));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/purchase-orders']! as Map;
    expect(body['supplier_id'], 's1');
    final lines = (body['lines']! as List).cast<Map>();
    expect(lines.length, 2);
    expect(lines[0]['product_id'], 'p1');
    expect(lines[0]['quantity'], '5');
    expect(lines[0]['unit_price'], '10');
    expect(lines[0]['supplier_product_code'], 'AC-1');
    expect(lines[1]['product_id'], 'p2');
    expect(lines[1]['quantity'], '30');
    expect(lines[1]['unit_price'], '4.5');
  });

  testWidgets('changing the supplier clears the selection with a message', (
    tester,
  ) async {
    await _open(tester, _http());
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    await tester.tap(find.byKey(const ValueKey('po-goods-check-p1')));
    await tester.pumpAndSettle();
    await _supplierPick(tester, 'bolt', 'SUP-2 · Bolt');
    expect(find.text('BLT-1 · Bolt'), findsOneWidget);
    expect(find.text('MOT-1 · Motor'), findsNothing);
    expect(find.byKey(const ValueKey('po-goods-cleared')), findsOneWidget);
    expect(find.textContaining('0 lines'), findsOneWidget);
    // Going back to the first supplier does not bring the old tick back.
    await _supplierPick(tester, 'acme', 'SUP-1 · Acme');
    expect(_checked(tester, 'p1'), isFalse);
  });
}
