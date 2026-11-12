import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/environments.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/tutorial/api_events.dart';
import 'package:tradocraft_app/features/tutorial/controller.dart';

import 'fake_http.dart';

const _ids = {
  'motorId': 'm1',
  'frameId': 'f1',
  'controllerId': 'c1',
  'cartId': 'k1',
};

/// A container whose stored progress says: these chapters are done, [active] is at step 0, and
/// the story already captured [values].
ProviderContainer _boot(
  FakeHttp http, {
  required List<String> completed,
  required String active,
  Map<String, String> values = const {},
}) {
  final kv = MemoryKvStore()
    ..data['tutorial.v1.e1.dev:a@x.test'] = jsonEncode({
      'completed': completed,
      'active': active,
      'step': 0,
      'values': {..._ids, ...values},
    });
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      kvStoreProvider.overrideWithValue(kv),
      tutorialScopeProvider.overrideWithValue(
        const TutorialScope(
          envId: 'e1',
          kind: EnvironmentKind.tutorial,
          who: 'dev:a@x.test',
        ),
      ),
      dioProvider.overrideWith((ref) {
        final d = fakeDio(http);
        d.interceptors.add(ApiEventInterceptor(ref.read(apiEventBusProvider)));
        return d;
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Map<String, Object?> _product(String id, String code, String type) => {
  'id': id,
  'code': code,
  'product_type': type,
};

FakeHttp _withProducts(Map<String, Object? Function(Object?)> routes) =>
    FakeHttp({
      'GET /api/v1/products': (_) => {
        'items': [
          _product('m1', 'TUT-MOTOR', 'purchased'),
          _product('f1', 'TUT-FRAME', 'purchased'),
          _product('c1', 'TUT-CTRL', 'purchased'),
          _product('k1', 'TUT-CART', 'manufactured'),
        ],
      },
      ...routes,
    });

void main() {
  group('chapter 2: suppliers', () {
    test('creating suppliers and price entries finishes the steps', () async {
      final http = FakeHttp({
        'POST /api/v1/suppliers': (b) => {
          'id': 's-${(b as Map)['code']}',
          'code': b['code'],
        },
        'POST /api/v1/suppliers/s-TUT-SUP-A/products/m1': (_) => {'id': 'x'},
        'POST /api/v1/suppliers/s-TUT-SUP-A/products/f1': (_) => {'id': 'x'},
        'POST /api/v1/suppliers/s-TUT-SUP-A/products/c1': (_) => {'id': 'x'},
        'POST /api/v1/suppliers/s-TUT-SUP-B/products/m1': (_) => {'id': 'x'},
        'POST /api/v1/suppliers/s-TUT-SUP-B/products/f1': (_) => {'id': 'x'},
      });
      final c = _boot(http, completed: ['welcome', 'product'], active: 'suppliers');
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      final dio = c.read(dioProvider);
      int step() => c.read(tutorialProvider).stepIndex;
      expect(step(), 0, reason: 'products not found: the needs step waits');
      t.next();
      t.routeChanged('/purchasing');
      expect(step(), 2);
      Future<void> sup(String code) => dio.post<Object?>(
        '/api/v1/suppliers',
        data: {'code': code, 'name': code},
      );
      await sup('OTHER');
      expect(step(), 2);
      await sup('TUT-SUP-A');
      expect(step(), 3);
      await sup('TUT-SUP-B');
      expect(step(), 4);
      expect(c.read(tutorialProvider).values['supplierBId'], 's-TUT-SUP-B');
      t.routeChanged('/suppliers/s-TUT-SUP-A');
      expect(step(), 5);
      Future<void> price(String s, String p) =>
          dio.post<Object?>('/api/v1/suppliers/$s/products/$p', data: {
            'unit_price': '1',
          });
      await price('s-TUT-SUP-B', 'm1'); // wrong supplier
      expect(step(), 5);
      await price('s-TUT-SUP-A', 'm1');
      await price('s-TUT-SUP-A', 'f1');
      await price('s-TUT-SUP-A', 'c1');
      expect(step(), 8);
      t.routeChanged('/suppliers/s-TUT-SUP-B');
      expect(step(), 9);
      await price('s-TUT-SUP-B', 'm1');
      expect(step(), 10);
      t.next();
      expect(c.read(tutorialProvider).completed, contains('suppliers'));
    });

    test('probes skip the needs step and existing suppliers and prices', () async {
      final http = _withProducts({
        'GET /api/v1/suppliers': (_) => [
          {'id': 'sa', 'code': 'TUT-SUP-A'},
          {'id': 'sb', 'code': 'TUT-SUP-B'},
        ],
        'GET /api/v1/suppliers/sa/products': (_) => [
          {'product_id': 'm1'},
          {'product_id': 'f1'},
          {'product_id': 'c1'},
        ],
        'GET /api/v1/suppliers/sb/products': (_) => [
          {'product_id': 'm1'},
        ],
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product'],
        active: 'suppliers',
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      await pumpEventQueue(times: 100);
      expect(c.read(tutorialProvider).stepIndex, 1, reason: 'needs skipped');
      t.routeChanged('/purchasing');
      await pumpEventQueue(times: 100);
      // both suppliers exist: openA is next (an OnRoute step)
      expect(c.read(tutorialProvider).stepIndex, 4);
      expect(c.read(tutorialProvider).values['supplierAId'], 'sa');
      t.routeChanged('/suppliers/sa');
      await pumpEventQueue(times: 100);
      expect(c.read(tutorialProvider).stepIndex, 8, reason: 'prices exist');
    });
  });

  group('chapter 3: buying and receiving', () {
    String status = 'draft';
    Map<String, Object?> po() => {
      'id': 'po1',
      'supplier_id': 'sa',
      'status': status,
      'lines': [
        for (final p in ['m1', 'f1', 'c1']) {'product_id': p},
      ],
    };

    test('order, approve, send, two receipts, stock', () async {
      status = 'draft';
      final http = FakeHttp({
        'POST /api/v1/purchase-orders': (_) => po(),
        'POST /api/v1/purchase-orders/po1/approve': (_) => po(),
        'POST /api/v1/purchase-orders/po1/send': (_) => po(),
        'POST /api/v1/purchase-orders/po1/receipts': (_) => {'id': 'g'},
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product', 'suppliers'],
        active: 'buying',
        values: {'supplierAId': 'sa'},
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      final dio = c.read(dioProvider);
      int step() => c.read(tutorialProvider).stepIndex;
      t.next(); // needs
      t.routeChanged('/purchasing');
      expect(step(), 2);
      Future<void> order(String supplier, List<String> products) =>
          dio.post<Object?>('/api/v1/purchase-orders', data: {
            'supplier_id': supplier,
            'lines': [
              for (final p in products) {'product_id': p},
            ],
          });
      await order('sa', ['m1', 'f1', 'c1']);
      expect(step(), 3);
      expect(c.read(tutorialProvider).values['poId'], 'po1');
      t.routeChanged('/purchase-orders/po1');
      expect(step(), 4);
      await dio.post<Object?>('/api/v1/purchase-orders/po1/approve');
      await dio.post<Object?>('/api/v1/purchase-orders/po1/send');
      expect(step(), 6);
      await dio.post<Object?>('/api/v1/purchase-orders/po1/receipts');
      expect(step(), 7);
      await dio.post<Object?>('/api/v1/purchase-orders/po1/receipts');
      expect(step(), 8);
      t.routeChanged('/stock');
      expect(step(), 9);
      t.next();
      expect(c.read(tutorialProvider).completed, contains('buying'));
    });

    test('the order step ignores another supplier and short orders', () async {
      var sup = 'sb';
      var lines = ['m1', 'f1', 'c1'];
      final http = FakeHttp({
        'POST /api/v1/purchase-orders': (_) => {
          'id': 'po9',
          'supplier_id': sup,
          'status': 'draft',
          'lines': [
            for (final p in lines) {'product_id': p},
          ],
        },
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product', 'suppliers'],
        active: 'buying',
        values: {'supplierAId': 'sa'},
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      t.next();
      t.routeChanged('/purchasing');
      final dio = c.read(dioProvider);
      await dio.post<Object?>('/api/v1/purchase-orders');
      expect(c.read(tutorialProvider).stepIndex, 2, reason: 'wrong supplier');
      sup = 'sa';
      lines = ['m1'];
      await dio.post<Object?>('/api/v1/purchase-orders');
      expect(c.read(tutorialProvider).stepIndex, 2, reason: 'one line only');
    });

    test('a probe with a missing placeholder sends no request', () async {
      final http = _withProducts({
        'GET /api/v1/purchase-orders': (_) => [
          {'id': 'po2', 'status': 'received'},
        ],
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product', 'suppliers'],
        active: 'buying',
      ); // no supplierAId captured
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      await pumpEventQueue(times: 100);
      t.routeChanged('/purchasing');
      await pumpEventQueue(times: 100);
      expect(http.requests, isNot(contains('GET /api/v1/purchase-orders')));
      expect(c.read(tutorialProvider).stepIndex, 2);
    });

    test('probes fast-forward over a received order', () async {
      final http = _withProducts({
        'GET /api/v1/purchase-orders': (_) => [
          {'id': 'po1', 'status': 'cancelled'},
          {'id': 'po2', 'status': 'received'},
        ],
        'GET /api/v1/purchase-orders/po2': (_) => {'status': 'received'},
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product', 'suppliers'],
        active: 'buying',
        values: {'supplierAId': 'sa'},
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      await pumpEventQueue(times: 100);
      t.routeChanged('/purchasing');
      await pumpEventQueue(times: 100);
      expect(c.read(tutorialProvider).values['poId'], 'po2');
      expect(
        http.queries.any((q) => q['supplier_id'] == 'sa'),
        isTrue,
        reason: '{supplierAId} is resolved in the probe query',
      );
      expect(c.read(tutorialProvider).stepIndex, 3);
      t.routeChanged('/purchase-orders/po2');
      await pumpEventQueue(times: 200);
      expect(c.read(tutorialProvider).stepIndex, 8, reason: 'only stock is left');
    });
  });

  group('chapter 4: invoices', () {
    test('create, approve, second invoice, dispute, pay', () async {
      final http = FakeHttp({
        'POST /api/v1/supplier-invoices': (b) =>
            (b as Map)['purchase_order_id'] == null
            ? {
                'id': 'i2',
                'invoice_number': (b)['invoice_number'],
                'purchase_order_id': null,
                'supplier_id': 'sa',
              }
            : {
                'id': 'i1',
                'invoice_number': 'ACME-1',
                'purchase_order_id': 'po1',
                'supplier_id': 'sa',
              },
        'POST /api/v1/supplier-invoices/i1/approve': (_) => {'id': 'i1'},
        'POST /api/v1/supplier-invoices/i2/dispute': (_) => {'id': 'i2'},
        'POST /api/v1/supplier-invoices/i1/mark-paid': (_) => {'id': 'i1'},
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product', 'suppliers', 'buying'],
        active: 'invoices',
        values: {'supplierAId': 'sa', 'poId': 'po1'},
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      final dio = c.read(dioProvider);
      int step() => c.read(tutorialProvider).stepIndex;
      t.next();
      t.routeChanged('/purchase-orders/po1');
      expect(step(), 2);
      await dio.post<Object?>(
        '/api/v1/supplier-invoices',
        data: {'purchase_order_id': 'po1'},
      );
      expect(step(), 3);
      t.next(); // match
      await dio.post<Object?>('/api/v1/supplier-invoices/i1/approve');
      expect(step(), 5);
      // Only the invoice numbered TUT-INV-002 counts as the second one.
      await dio.post<Object?>(
        '/api/v1/supplier-invoices',
        data: {'purchase_order_id': 'po1'},
      );
      expect(step(), 5);
      await dio.post<Object?>(
        '/api/v1/supplier-invoices',
        data: {'purchase_order_id': null, 'invoice_number': 'OTHER-9'},
      );
      expect(step(), 5);
      await dio.post<Object?>(
        '/api/v1/supplier-invoices',
        data: {'purchase_order_id': null, 'invoice_number': 'TUT-INV-002'},
      );
      expect(step(), 6);
      expect(c.read(tutorialProvider).values['invoice2Id'], 'i2');
      t.routeChanged('/supplier-invoices/i1');
      expect(step(), 6, reason: 'the second invoice must be opened, not the first');
      t.routeChanged('/supplier-invoices/i2');
      expect(step(), 7);
      t.next(); // mismatch
      await dio.post<Object?>('/api/v1/supplier-invoices/i2/dispute');
      expect(step(), 9);
      t.next(); // tolerances
      await dio.post<Object?>('/api/v1/supplier-invoices/i1/mark-paid');
      expect(step(), 11);
      t.next();
      expect(c.read(tutorialProvider).completed, contains('invoices'));
    });

    test('probes skip finished work', () async {
      final http = FakeHttp({
        'GET /api/v1/purchase-orders/po1': (_) => {'status': 'received'},
        'GET /api/v1/supplier-invoices': (_) => {
          'items': [
            {'id': 'i1', 'invoice_number': 'ACME-1', 'purchase_order_id': 'po1'},
            {'id': 'x', 'invoice_number': 'OTHER-9', 'purchase_order_id': null},
            {'id': 'i2', 'invoice_number': 'TUT-INV-002', 'purchase_order_id': null},
          ],
        },
        'GET /api/v1/supplier-invoices/i1': (_) => {'status': 'paid'},
        'GET /api/v1/supplier-invoices/i2': (_) => {'status': 'disputed'},
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product', 'suppliers', 'buying'],
        active: 'invoices',
        values: {'supplierAId': 'sa', 'poId': 'po1'},
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      await pumpEventQueue(times: 100);
      expect(c.read(tutorialProvider).stepIndex, 1, reason: 'needs skipped');
      t.routeChanged('/purchase-orders/po1');
      await pumpEventQueue(times: 200);
      // create, approve (paid counts), second and dispute are done; the match explanations
      // and the tolerances wait for Next.
      expect(c.read(tutorialProvider).stepIndex, 3);
      t.next(); // match
      await pumpEventQueue(times: 200);
      expect(c.read(tutorialProvider).stepIndex, 6, reason: 'approve and second are done');
      t.next();
      await pumpEventQueue(times: 200);
      expect(c.read(tutorialProvider).values['invoice2Id'], 'i2');
      t.routeChanged('/supplier-invoices/i2');
      await pumpEventQueue(times: 200);
      expect(c.read(tutorialProvider).stepIndex, 7);
      t.next(); // mismatch -> dispute done -> tolerances
      await pumpEventQueue(times: 200);
      expect(c.read(tutorialProvider).stepIndex, 9, reason: 'dispute is done');
      t.next(); // tolerances
      await pumpEventQueue(times: 200);
      expect(c.read(tutorialProvider).stepIndex, 11, reason: 'paid is done');
      expect(
        http.queries.any((q) => q['purchase_order_id'] == 'po1'),
        isTrue,
        reason: '{poId} is resolved in the probe query',
      );
      expect(
        http.queries.any((q) => q['supplier_id'] == 'sa'),
        isTrue,
        reason: '{supplierAId} is resolved in the probe query',
      );
      expect(
        http.queries.any((q) => q.values.any((v) => '$v'.contains('{'))),
        isFalse,
        reason: 'no unresolved placeholder is sent',
      );
    });
  });
}
