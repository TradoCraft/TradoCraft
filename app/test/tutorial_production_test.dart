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
  group('chapter 5: manufacturing', () {
    test('division, release, assign, start, complete', () async {
      final http = FakeHttp({
        'POST /api/v1/production/divisions': (b) => {
          'id': 'd1',
          'code': (b as Map)['code'],
          'members': [
            for (final u in b['member_user_ids'] as List) {'user_id': u},
          ],
        },
        'POST /api/v1/production-orders': (b) => {
          'id': 'po1',
          'product_id': (b as Map)['product_id'],
        },
        'PUT /api/v1/production-orders/po1': (b) => {
          'id': 'po1',
          'division_id': (b as Map)['division_id'],
        },
        'POST /api/v1/production-orders/po1/start': (_) => {'id': 'po1'},
        'POST /api/v1/production-orders/po1/complete': (_) => {'id': 'po1'},
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product', 'suppliers', 'buying', 'invoices'],
        active: 'manufacturing',
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      final dio = c.read(dioProvider);
      int step() => c.read(tutorialProvider).stepIndex;
      t.next(); // needs
      t.routeChanged('/production/divisions');
      expect(step(), 2);
      Future<void> division(String code, List<String> members) =>
          dio.post<Object?>(
            '/api/v1/production/divisions',
            data: {'code': code, 'name': code, 'member_user_ids': members},
          );
      await division('OTHER', ['u1']);
      await division('TUT-ASM', []);
      expect(step(), 2, reason: 'a member is needed for the My divisions demo');
      await division('TUT-ASM', ['u1']);
      expect(step(), 3);
      expect(c.read(tutorialProvider).values['divisionId'], 'd1');
      t.routeChanged('/production/divisions');
      expect(step(), 3, reason: 'the divisions page is not the queue');
      t.routeChanged('/production');
      expect(step(), 4);
      await dio.post<Object?>(
        '/api/v1/production-orders',
        data: {'product_id': 'other', 'quantity': '5'},
      );
      expect(step(), 4);
      await dio.post<Object?>(
        '/api/v1/production-orders',
        data: {'product_id': 'k1', 'quantity': '5'},
      );
      expect(step(), 5);
      await dio.put<Object?>(
        '/api/v1/production-orders/po1',
        data: {'division_id': 'zzz'},
      );
      expect(step(), 5, reason: 'the story division is needed');
      await dio.put<Object?>(
        '/api/v1/production-orders/po1',
        data: {'division_id': 'd1'},
      );
      expect(step(), 6);
      await dio.post<Object?>('/api/v1/production-orders/po1/start');
      await dio.post<Object?>('/api/v1/production-orders/po1/complete');
      expect(step(), 8);
      t.routeChanged('/stock');
      expect(step(), 9);
      t.next();
      expect(c.read(tutorialProvider).completed, contains('manufacturing'));
    });

    test('probes skip a finished production order', () async {
      final http = _withProducts({
        'GET /api/v1/production/divisions': (_) => [
          {'id': 'd1', 'code': 'TUT-ASM', 'members': [{'user_id': 'u'}]},
        ],
        'GET /api/v1/production-orders': (_) => {
          'items': [
            {'id': 'x', 'product_id': 'k1', 'status': 'cancelled'},
            {'id': 'po2', 'product_id': 'k1', 'status': 'completed'},
          ],
        },
        'GET /api/v1/production-orders/po2': (_) => {
          'status': 'completed',
          'division_id': 'd1',
        },
      });
      final c = _boot(
        http,
        completed: ['welcome', 'product', 'suppliers', 'buying', 'invoices'],
        active: 'manufacturing',
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      await pumpEventQueue(times: 100);
      expect(c.read(tutorialProvider).stepIndex, 1);
      t.routeChanged('/production/divisions');
      await pumpEventQueue(times: 100);
      // the division exists: the queue explanation waits for the user
      expect(c.read(tutorialProvider).stepIndex, 3);
      t.routeChanged('/production');
      await pumpEventQueue(times: 200);
      expect(c.read(tutorialProvider).values['productionId'], 'po2');
      expect(
        http.queries.any((q) => q['q'] == 'TUT-CART'),
        isTrue,
        reason: 'the production probe asks for the cart',
      );
      expect(c.read(tutorialProvider).stepIndex, 8, reason: 'only the stock is left');
    });
  });

  group('chapter 6: prices', () {
    test('zone, price in the zone, price in another zone', () async {
      final http = FakeHttp({
        'POST /api/v1/price-zones': (b) => {
          'id': 'z-new',
          'code': (b as Map)['code'],
        },
        'POST /api/v1/products/k1/prices': (b) => {
          'zone_id': (b as Map)['zone_id'],
        },
      });
      final c = _boot(
        http,
        completed: [
          'welcome', 'product', 'suppliers', 'buying', 'invoices', 'manufacturing',
        ],
        active: 'prices',
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      final dio = c.read(dioProvider);
      int step() => c.read(tutorialProvider).stepIndex;
      t.next();
      t.routeChanged('/admin');
      expect(step(), 2);
      await dio.post<Object?>(
        '/api/v1/price-zones',
        data: {'code': 'Z9', 'name': 'x'},
      );
      expect(step(), 2);
      await dio.post<Object?>(
        '/api/v1/price-zones',
        data: {'code': 'TUT-EXPORT', 'name': 'Export zone'},
      );
      expect(step(), 3);
      t.routeChanged('/products/k1');
      expect(step(), 4);
      Future<void> price(String zone) => dio.post<Object?>(
        '/api/v1/products/k1/prices',
        data: {'zone_id': zone, 'unit_price': '1', 'valid_from': '2026-01-01'},
      );
      await price('z1');
      expect(step(), 4, reason: 'the new zone comes first');
      await price('z-new');
      expect(step(), 5);
      await price('z-new');
      expect(step(), 5, reason: 'another zone is needed');
      await price('z1');
      expect(step(), 6);
      t.next();
      expect(c.read(tutorialProvider).completed, contains('prices'));
    });

    test('probes recognise existing zone and prices', () async {
      final http = _withProducts({
        'GET /api/v1/price-zones': (_) => [
          {'id': 'z1', 'code': 'Z1'},
          {'id': 'zx', 'code': 'TUT-EXPORT'},
        ],
        'GET /api/v1/products/k1/prices': (_) => [
          {'zone_id': 'zx'},
          {'zone_id': 'z1'},
        ],
      });
      final c = _boot(
        http,
        completed: [
          'welcome', 'product', 'suppliers', 'buying', 'invoices', 'manufacturing',
        ],
        active: 'prices',
      );
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.resume();
      await pumpEventQueue(times: 100);
      t.routeChanged('/admin');
      await pumpEventQueue(times: 100);
      expect(c.read(tutorialProvider).values['zoneId'], 'zx');
      expect(c.read(tutorialProvider).stepIndex, 3);
      t.routeChanged('/products/k1');
      await pumpEventQueue(times: 200);
      expect(c.read(tutorialProvider).stepIndex, 6);
    });
  });
}
