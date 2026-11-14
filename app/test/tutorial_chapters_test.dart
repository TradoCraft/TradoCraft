import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/environments.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/products/bom_tab.dart';
import 'package:tradocraft_app/features/products/product_form.dart';
import 'package:tradocraft_app/features/tutorial/api_events.dart';
import 'package:tradocraft_app/features/tutorial/controller.dart';
import 'package:tradocraft_app/features/tutorial/missions.dart';
import 'package:tradocraft_app/features/tutorial/model.dart';
import 'package:tradocraft_app/features/tutorial/strings.dart';
import 'package:tradocraft_app/features/tutorial/targets.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _product(String id, String code, String type) => {
  'id': id,
  'code': code,
  'name': code,
  'description': '',
  'unit': 'pcs',
  'product_type': type,
  'vat_rate': '21',
  'tracking': 'none',
  'pricing_type': 'list',
  'active': true,
};

ProviderContainer _boot(FakeHttp http, {MemoryKvStore? kv}) {
  final c = ProviderContainer(
    // Failed requests of unrelated providers must not leave retry timers behind.
    retry: (_, _) => null,
    overrides: [
      kvStoreProvider.overrideWithValue(kv ?? MemoryKvStore()),
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

void main() {
  group('strings', () {
    test('every key of every mission exists in all five languages', () {
      final keys = allTutorialKeys(allMissions);
      expect(keys.toSet(), hasLength(keys.length), reason: 'no duplicate keys');
      for (final code in ['en', 'nl', 'fr', 'de', 'es']) {
        final arb = jsonDecode(
          File('lib/l10n/app_$code.arb').readAsStringSync(),
        ) as Map<String, dynamic>;
        final l = lookupAppLocalizations(Locale(code));
        for (final k in keys) {
          expect(arb[k], isA<String>(), reason: '$k missing in $code');
          expect(
            (arb[k] as String).trim(),
            isNotEmpty,
            reason: '$k empty in $code',
          );
          expect(
            tutorialTextOrNull(l, k),
            arb[k],
            reason: '$k is not in strings.dart (or differs) for $code',
          );
        }
      }
    });

    test('step ids are unique within a mission and chapters have steps', () {
      for (final m in allMissions) {
        expect(m.steps, isNotEmpty);
        expect(m.steps.map((s) => s.id).toSet(), hasLength(m.steps.length));
      }
      expect(
        allMissions.map((m) => m.id).toSet(),
        hasLength(allMissions.length),
      );
    });
  });

  group('chapter 0: welcome', () {
    test('explanations are read with Next, the last step waits for the products page', () async {
      final c = _boot(FakeHttp({}));
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      expect(await t.start('welcome'), StartResult.started);
      for (var i = 0; i < 4; i++) {
        expect(c.read(tutorialProvider).stepIndex, i);
        t.next();
      }
      expect(c.read(tutorialProvider).stepIndex, 4);
      expect(c.read(tutorialProvider).completed, isEmpty);
      t.routeChanged('/quotations');
      expect(c.read(tutorialProvider).completed, isEmpty);
      t.routeChanged('/products');
      expect(c.read(tutorialProvider).completed, {'welcome'});
      expect(t.currentChapter?.id, 'product', reason: 'chapter 1 is unlocked');
    });
  });

  group('chapter 1: your first product', () {
    FakeHttp server() => FakeHttp({
      'POST /api/v1/products': (b) {
        final body = b as Map;
        final code = body['code'] as String;
        return {..._product('id-$code', code, body['product_type'] as String)};
      },
      'POST /api/v1/products/id-TUT-CART/boms': (_) => {'id': 'bom1'},
      'PUT /api/v1/boms/bom1': (b) => {
        'id': 'bom1',
        'status': 'draft',
        'lines': [
          for (final l in (b as Map)['lines'] as List)
            {'component_product_id': (l as Map)['component_product_id']},
        ],
      },
      'POST /api/v1/boms/bom1/activate': (_) => {
        'id': 'bom1',
        'status': 'active',
      },
    });

    test('a full run through FakeHttp events, with the cart id used in the deep link', () async {
      final http = server();
      final c = _boot(http);
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.start('welcome');
      await t.skipChapter();
      expect(await t.start('product'), StartResult.started);
      final dio = c.read(dioProvider);
      int step() => c.read(tutorialProvider).stepIndex;

      // open
      t.routeChanged('/products');
      expect(step(), 1);

      Future<void> create(String code, String type) => dio.post<Object?>(
        '/api/v1/products',
        data: {'code': code, 'name': code, 'product_type': type},
      );
      // A wrong code or type does not count.
      await create('OTHER', 'purchased');
      await create('TUT-MOTOR', 'manufactured');
      expect(step(), 1);
      await create('TUT-MOTOR', 'purchased');
      expect(step(), 2);
      await create('TUT-FRAME', 'purchased');
      await create('TUT-CTRL', 'purchased');
      expect(step(), 4);
      await create('TUT-CART', 'manufactured');
      expect(step(), 5);
      final values = c.read(tutorialProvider).values;
      expect(values['motorId'], 'id-TUT-MOTOR');
      expect(values['cartId'], 'id-TUT-CART');

      // open the cart: the deep link comes from the captured id
      final cartStep = allMissions[1].steps[5];
      expect(
        c.read(tutorialProvider).context.resolve(cartStep.route!),
        '/products/id-TUT-CART',
      );
      t.routeChanged('/products/id-TUT-MOTOR');
      expect(step(), 5, reason: 'another product does not count');
      t.routeChanged('/products/id-TUT-CART');
      expect(step(), 6);
      t.next(); // BOM tab
      expect(step(), 7);

      await dio.post<Object?>('/api/v1/products/id-TUT-CART/boms');
      expect(step(), 8);

      Future<void> save(List<String> ids) => dio.put<Object?>(
        '/api/v1/boms/bom1',
        data: {
          'notes': '',
          'lines': [
            for (final id in ids) {'component_product_id': id, 'quantity': '1'},
          ],
        },
      );
      await save(['id-TUT-MOTOR', 'id-TUT-FRAME']);
      expect(step(), 8, reason: 'three lines are needed');
      await save(['id-TUT-MOTOR', 'id-TUT-FRAME', 'id-TUT-OTHER']);
      expect(step(), 8, reason: 'the three components of the story are needed');
      await save(['id-TUT-MOTOR', 'id-TUT-FRAME', 'id-TUT-CTRL']);
      expect(step(), 9);

      await dio.post<Object?>('/api/v1/boms/bom1/activate');
      expect(step(), 10);
      t.next();
      expect(c.read(tutorialProvider).completed, contains('product'));
    });

    test(
      'probes skip what is already done when the chapter is replayed',
      () async {
        final http = FakeHttp({
          'GET /api/v1/products': (_) => {
            'total': 4,
            'items': [
              _product('m1', 'TUT-MOTOR', 'purchased'),
              _product('f1', 'TUT-FRAME', 'purchased'),
              _product('c1', 'TUT-CTRL', 'purchased'),
              _product('k1', 'TUT-CART', 'manufactured'),
            ],
          },
          'GET /api/v1/boms/b': (_) => {
            'id': 'b',
            'status': 'active',
            'lines': [
              for (final id in ['m1', 'f1', 'c1']) {'component_product_id': id},
            ],
          },
          'GET /api/v1/products/k1/boms': (_) => [
            {'id': 'b', 'status': 'active', 'line_count': 3},
          ],
        });
        final c = _boot(http);
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        await t.skipChapter('welcome');
        await t.start('product');
        t.routeChanged('/products'); // step open
        await pumpEventQueue(times: 200);
        var s = c.read(tutorialProvider);
        // The four products exist: the story jumps to "open the cart", with the ids captured.
        expect(s.stepIndex, 5);
        expect(s.values['cartId'], 'k1');
        expect(s.values['motorId'], 'm1');
        // Opening the cart then lets the BOM probes finish revision, lines and activation.
        t.routeChanged('/products/k1');
        t.next(); // bomTab
        await pumpEventQueue(times: 200);
        s = c.read(tutorialProvider);
        expect(
          s.stepIndex,
          10,
          reason: 'revision, lines and activation are done',
        );
        expect(s.completed, isEmpty);
        t.next();
        expect(
          c.read(tutorialProvider).completed,
          {'welcome', 'product'}.difference({'welcome'}),
        );
      },
    );
  });

  group('probe precision', () {
    test(
      'a product with the right code but another type does not count',
      () async {
        final http = FakeHttp({
          'GET /api/v1/products': (_) => {
            'total': 1,
            'items': [_product('x1', 'TUT-MOTOR', 'manufactured')],
          },
        });
        final c = _boot(http);
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        await t.skipChapter('welcome');
        await t.start('product');
        t.routeChanged('/products');
        await pumpEventQueue(times: 200);
        expect(c.read(tutorialProvider).stepIndex, 1);
        expect(c.read(tutorialProvider).values.containsKey('motorId'), isFalse);
      },
    );

    test(
      'the lines probe checks the lines of the story BOM, not a line count',
      () async {
        final http = FakeHttp({
          'GET /api/v1/products': (_) => {'total': 0, 'items': <Object?>[]},
          'GET /api/v1/products/k1/boms': (_) => [
            {'id': 'other', 'status': 'active', 'line_count': 9},
            {'id': 'b', 'status': 'draft', 'line_count': 3},
          ],
          'GET /api/v1/boms/b': (_) => {
            'id': 'b',
            'status': 'draft',
            'lines': [
              for (final id in ['m1', 'f1', 'zzz'])
                {'component_product_id': id},
            ],
          },
        });
        final kv = MemoryKvStore()
          ..data['tutorial.v1.e1.dev:a@x.test'] = jsonEncode({
            'completed': ['welcome'],
            'active': 'product',
            'step': 7,
            'values': {
              'motorId': 'm1',
              'frameId': 'f1',
              'controllerId': 'c1',
              'cartId': 'k1',
            },
          });
        final c = _boot(http, kv: kv);
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        await t.resume();
        await pumpEventQueue(times: 200);
        final s = c.read(tutorialProvider);
        expect(
          s.values['bomId'],
          'b',
          reason: 'the cart draft, not the other BOM',
        );
        expect(s.stepIndex, 8, reason: 'revision exists, lines are not right');
      },
    );
  });

  group('tutorial hooks in the screens', () {
    Widget app(ProviderContainer c, Widget child) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

    testWidgets('the product form registers its save button', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.write']),
      });
      final c = _boot(http);
      await tester.pumpWidget(app(c, const ProductForm()));
      await tester.pumpAndSettle();
      expect(c.read(tutorialTargetsProvider)['product-form-save'], isNotNull);
      await tester.pumpWidget(const SizedBox());
      expect(c.read(tutorialTargetsProvider)['product-form-save'], isNull);
    });

    testWidgets('the BOM tab registers its revision and component controls', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['bom.write', 'products.read']),
        'GET /api/v1/products/p1/boms': (_) => <Object?>[],
      });
      final c = _boot(http);
      final product = Product.fromJson(
        _product('p1', 'TUT-CART', 'manufactured'),
      );
      await tester.pumpWidget(app(c, BomTab(product: product)));
      await tester.pumpAndSettle();
      expect(c.read(tutorialTargetsProvider)['bom-new-revision'], isNotNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
