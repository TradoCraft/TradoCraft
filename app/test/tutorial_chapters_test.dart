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
import 'package:tradocraft_app/features/tutorial/conveyor_svg.dart';
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
  ...pricingFlags('list'),
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
      expect(
        t.currentChapter?.id,
        'conveyors',
        reason: 'chapter 1 is unlocked',
      );
    });
  });

  group('chapter 1: conveyor belts & motors', () {
    test('SVG assembly diagram renders with or without motor', () {
      final with3p = buildConveyorAssemblySvg(withMotor: true, threePhase: true);
      final with1p = buildConveyorAssemblySvg(withMotor: true, threePhase: false);
      final without = buildConveyorAssemblySvg(withMotor: false);
      expect(with3p, contains('MOT-3P-055'));
      expect(with3p, contains('VFD'));
      expect(with1p, contains('MOT-1P-037'));
      expect(without, contains('without motor'));
      expect(without, isNot(contains('MOT-3P-055')));
    });

    test(
      'assistance creates conveyor products and a usable active BOM',
      () async {
        final products = [_product('lower', 'mot-3p-055', 'purchased')];
        Map<String, Object?>? bom;
        final http = FakeHttp({
          'GET /api/v1/products': (_) => {'items': products},
          'POST /api/v1/products': (body) {
            final input = body as Map;
            final code = input['code'] as String;
            final saved = _product(
              'id-$code',
              code,
              input['product_type'] as String,
            );
            products.add(saved);
            return saved;
          },
          'GET /api/v1/products/id-CONV-BELT-1M/boms': (_) => [?bom],
          'POST /api/v1/products/id-CONV-BELT-1M/boms': (_) => bom = {
            'id': 'bom1',
            'product_id': 'id-CONV-BELT-1M',
            'status': 'draft',
            'notes': 'Keep this note',
            'lines': [
              {'component_product_id': 'id-MOT-3P-055', 'quantity': '2'},
            ],
          },
          'GET /api/v1/boms/bom1': (_) => bom,
          'PUT /api/v1/boms/bom1': (body) =>
              bom = {...bom!, ...Map<String, Object?>.from(body as Map)},
          'POST /api/v1/boms/bom1/activate': (_) =>
              bom = {...bom!, 'status': 'active'},
        });
        final c = _boot(http);
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        await t.skipChapter('welcome');
        await t.start('conveyors');
        t.routeChanged('/products');

        for (final id in ['motor1p', 'motor', 'vfd', 'conveyor']) {
          expect(t.step?.id, id);
          await t.runAction();
        }
        expect(products.map((p) => p['code']), [
          'mot-3p-055',
          'MOT-1P-037',
          'MOT-3P-055',
          'VFD-3P-055',
          'CONV-BELT-1M',
        ]);
        expect(c.read(tutorialProvider).values['motorId'], 'id-MOT-3P-055');
        t.routeChanged('/products/id-CONV-BELT-1M');
        t.next(); // svgPreview -> bomTab
        t.next(); // bomTab -> revision
        for (final id in ['revision', 'lines', 'activate']) {
          expect(t.step?.id, id);
          await t.runAction();
        }
        expect(t.step?.id, 'done');
        expect(bom?['status'], 'active');
        expect(bom?['notes'], 'Keep this note');
        expect(
          {
            for (final line in bom?['lines'] as List)
              (line as Map)['component_product_id']: line['quantity'],
          },
          {'id-MOT-3P-055': '2', 'id-VFD-3P-055': '1'},
        );
      },
    );

    FakeHttp server() => FakeHttp({
      'POST /api/v1/products': (b) {
        final body = b as Map;
        final code = body['code'] as String;
        return {..._product('id-$code', code, body['product_type'] as String)};
      },
      'POST /api/v1/products/id-CONV-BELT-1M/boms': (_) => {'id': 'bom1'},
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

    test('a full run through FakeHttp events, with the conveyor id used in the deep link', () async {
      final http = server();
      final c = _boot(http);
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      await t.start('welcome');
      await t.skipChapter();
      expect(await t.start('conveyors'), StartResult.started);
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
      await create('MOT-1P-037', 'manufactured');
      expect(step(), 1);
      await create('MOT-1P-037', 'purchased');
      expect(step(), 2);
      await create('MOT-3P-055', 'purchased');
      await create('VFD-3P-055', 'purchased');
      expect(step(), 4);
      await create('CONV-BELT-1M', 'manufactured');
      expect(step(), 5);
      final values = c.read(tutorialProvider).values;
      expect(values['motorId'], 'id-MOT-3P-055');
      expect(values['cartId'], 'id-CONV-BELT-1M');

      // open the conveyor: the deep link comes from the captured id
      final conveyorStep = allMissions[1].steps[5];
      expect(
        c.read(tutorialProvider).context.resolve(conveyorStep.route!),
        '/products/id-CONV-BELT-1M',
      );
      t.routeChanged('/products/id-MOT-3P-055');
      expect(step(), 5, reason: 'another product does not count');
      t.routeChanged('/products/id-CONV-BELT-1M');
      expect(step(), 6);
      t.next(); // svgPreview
      expect(step(), 7);
      t.next(); // bomTab
      expect(step(), 8);

      await dio.post<Object?>('/api/v1/products/id-CONV-BELT-1M/boms');
      expect(step(), 9);

      Future<void> save(List<String> ids) => dio.put<Object?>(
        '/api/v1/boms/bom1',
        data: {
          'notes': '',
          'lines': [
            for (final id in ids) {'component_product_id': id, 'quantity': '1'},
          ],
        },
      );
      await save(['id-MOT-3P-055']);
      expect(step(), 9, reason: 'both lines are needed');
      await save(['id-MOT-3P-055', 'id-OTHER']);
      expect(step(), 9, reason: 'the two components of the story are needed');
      await save(['id-MOT-3P-055', 'id-VFD-3P-055']);
      expect(step(), 10);

      await dio.post<Object?>('/api/v1/boms/bom1/activate');
      expect(step(), 11);
      t.next();
      expect(c.read(tutorialProvider).completed, contains('conveyors'));
    });

    test(
      'probes skip what is already done when the chapter is replayed',
      () async {
        final http = FakeHttp({
          'GET /api/v1/products': (_) => {
            'total': 4,
            'items': [
              _product('m1p', 'MOT-1P-037', 'purchased'),
              _product('m1', 'MOT-3P-055', 'purchased'),
              _product('v1', 'VFD-3P-055', 'purchased'),
              _product('k1', 'CONV-BELT-1M', 'manufactured'),
            ],
          },
          'GET /api/v1/boms/b': (_) => {
            'id': 'b',
            'status': 'active',
            'lines': [
              for (final id in ['m1', 'v1']) {'component_product_id': id},
            ],
          },
          'GET /api/v1/products/k1/boms': (_) => [
            {'id': 'b', 'status': 'active', 'line_count': 2},
          ],
        });
        final c = _boot(http);
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        await t.skipChapter('welcome');
        await t.start('conveyors');
        t.routeChanged('/products'); // step open
        await pumpEventQueue(times: 200);
        var s = c.read(tutorialProvider);
        // The products exist: the story jumps to "openConveyor", with the ids captured.
        expect(s.stepIndex, 5);
        expect(s.values['cartId'], 'k1');
        expect(s.values['motorId'], 'm1');
        // Opening the conveyor then lets the BOM probes finish revision, lines and activation.
        t.routeChanged('/products/k1');
        t.next(); // svgPreview
        t.next(); // bomTab
        await pumpEventQueue(times: 200);
        s = c.read(tutorialProvider);
        expect(
          s.stepIndex,
          11,
          reason: 'revision, lines and activation are done',
        );
        expect(s.completed, isEmpty);
        t.next();
        expect(
          c.read(tutorialProvider).completed,
          {'welcome', 'conveyors'}.difference({'welcome'}),
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
            'items': [_product('x1', 'MOT-1P-037', 'manufactured')],
          },
        });
        final c = _boot(http);
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        await t.skipChapter('welcome');
        await t.start('conveyors');
        t.routeChanged('/products');
        await pumpEventQueue(times: 200);
        expect(c.read(tutorialProvider).stepIndex, 1);
        expect(c.read(tutorialProvider).values.containsKey('motor1pId'), isFalse);
      },
    );

    test(
      'the lines probe checks the lines of the story BOM, not a line count',
      () async {
        final http = FakeHttp({
          'GET /api/v1/products': (_) => {'total': 0, 'items': <Object?>[]},
          'GET /api/v1/products/k1/boms': (_) => [
            {'id': 'other', 'status': 'active', 'line_count': 9},
            {'id': 'b', 'status': 'draft', 'line_count': 2},
          ],
          'GET /api/v1/boms/b': (_) => {
            'id': 'b',
            'status': 'draft',
            'lines': [
              for (final id in ['m1', 'zzz'])
                {'component_product_id': id},
            ],
          },
        });
        final kv = MemoryKvStore()
          ..data['tutorial.v1.e1.dev:a@x.test'] = jsonEncode({
            'completed': ['welcome'],
            'active': 'conveyors',
            'step': 8,
            'values': {
              'motorId': 'm1',
              'frameId': 'v1',
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
          reason: 'the conveyor draft, not the other BOM',
        );
        expect(s.stepIndex, 9, reason: 'revision exists, lines are not right');
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
        _product('p1', 'CONV-BELT-1M', 'manufactured'),
      );
      await tester.pumpWidget(app(c, BomTab(product: product)));
      await tester.pumpAndSettle();
      expect(c.read(tutorialTargetsProvider)['bom-new-revision'], isNotNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('chapter 14: custom product properties', () {
    test('assist creates attribute definitions and fills PLC-BASE properties', () async {
      final defs = <Map<String, Object?>>[];
      final ctrlAttrs = <Map<String, Object?>>[];
      final http = FakeHttp({
        'GET /api/v1/products': (_) => {
          'items': [_product('ctrl1', 'PLC-BASE', 'purchased')],
          'total': 1,
        },
        'GET /api/v1/attribute-definitions': (_) => defs,
        'POST /api/v1/attribute-definitions': (body) {
          final input = Map<String, Object?>.from(body as Map);
          final created = {'id': 'def-${defs.length + 1}', ...input};
          defs.add(created);
          return created;
        },
        'GET /api/v1/products/ctrl1/attributes': (_) => ctrlAttrs,
        'PUT /api/v1/products/ctrl1/attributes': (body) {
          ctrlAttrs
            ..clear()
            ..addAll((body as List).cast<Map<String, Object?>>());
          return ctrlAttrs;
        },
      });
      final c = _boot(http);
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      for (final m in allMissions) {
        if (m.id == 'attributes') break;
        await t.skipChapter(m.id);
      }
      expect(await t.start('attributes'), StartResult.started);
      await pumpEventQueue();
      // `needs` probe captures controllerId and advances to `intro`.
      expect(c.read(tutorialProvider).stepIndex, 1);
      expect(c.read(tutorialProvider).values['controllerId'], 'ctrl1');

      // `intro` -> `openAdmin` -> `relays`
      t.next();
      expect(c.read(tutorialProvider).stepIndex, 2);
      t.routeChanged('/admin');
      expect(c.read(tutorialProvider).stepIndex, 3);

      // Assist each of the 7 attribute definition steps.
      for (final expectedKey in [
        'relay_count',
        'fet_count',
        'digital_inputs',
        'analog_4_20ma_inputs',
        'rs485_ports',
        'i2c_bus',
        'licensed_outputs_tier',
      ]) {
        await t.runAction();
        expect(defs.map((d) => d['key']), contains(expectedKey));
      }

      // `openController` -> `suitabilityTab` -> `fillProperties` -> `done`
      t.routeChanged('/products/ctrl1');
      expect(c.read(tutorialProvider).stepIndex, 11);
      t.next();
      expect(c.read(tutorialProvider).stepIndex, 12);
      await t.runAction();
      expect(c.read(tutorialProvider).stepIndex, 13);
      expect(
        ctrlAttrs.map((a) => '${a['key']}=${a['value']}'),
        containsAll([
          'relay_count=4',
          'fet_count=6',
          'digital_inputs=8',
          'analog_4_20ma_inputs=2',
          'rs485_ports=2',
          'i2c_bus=true',
          'licensed_outputs_tier=10',
        ]),
      );
      t.next();
      expect(c.read(tutorialProvider).completed, contains('attributes'));
    });

    test('assist reactivates inactive attribute definition and refuses inactive PLC-BASE', () async {
      final inactiveCtrl = {..._product('ctrl1', 'PLC-BASE', 'purchased'), 'active': false};
      final products = [inactiveCtrl];
      final defs = <Map<String, Object?>>[
        {
          'id': 'def-1',
          'key': 'relay_count',
          'label': 'Relay outputs',
          'kind': 'number',
          'scope': 'product',
          'sort_order': 10,
          'active': false,
        },
      ];
      var postDefCount = 0;
      var putDefCount = 0;
      final http = FakeHttp({
        'GET /api/v1/products': (_) => {'items': products, 'total': 1},
        'GET /api/v1/attribute-definitions': (_) => defs,
        'POST /api/v1/attribute-definitions': (_) {
          postDefCount++;
          return {};
        },
        'PUT /api/v1/attribute-definitions/def-1': (body) {
          putDefCount++;
          final input = Map<String, Object?>.from(body as Map);
          defs[0] = {'id': 'def-1', ...input};
          return defs[0];
        },
      });
      final c = _boot(http);
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      for (final m in allMissions) {
        if (m.id == 'attributes') break;
        await t.skipChapter(m.id);
      }
      await t.start('attributes');
      await pumpEventQueue();
      // Inactive PLC-BASE stays on `needs` and assist reports it instead of duplicating.
      expect(c.read(tutorialProvider).stepIndex, 0);
      await t.runAction();
      expect(c.read(tutorialProvider).actionError?.reason, contains('Active'));
      expect(products, hasLength(1));

      // Activate PLC-BASE and advance to `relays`.
      inactiveCtrl['active'] = true;
      t.next(); // -> intro
      t.next(); // -> openAdmin
      t.routeChanged('/admin'); // -> relays
      expect(c.read(tutorialProvider).stepIndex, 3);
      await t.runAction();
      expect(putDefCount, 1);
      expect(postDefCount, 0);
      expect(defs[0]['active'], isTrue);
    });
  });
}
