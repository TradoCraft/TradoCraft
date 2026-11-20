import 'dart:async';
import 'dart:convert';

import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/environments.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/tutorial/api_events.dart';
import 'package:tradocraft_app/features/tutorial/controller.dart';
import 'package:tradocraft_app/features/tutorial/missions.dart';
import 'package:tradocraft_app/features/tutorial/model.dart';
import 'package:tradocraft_app/features/tutorial/overlay.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

/// Chapter one: two read-only steps, the last one is the closing step.
const _one = Mission(
  id: 'one',
  steps: [
    MissionStep(id: 'a'),
    MissionStep(id: 'done'),
  ],
);

/// Chapter two: starts with a "needs" step that probes the server, then a closing step.
final _two = Mission(
  id: 'two',
  steps: [
    MissionStep(
      id: 'needs',
      probe: Probe(
        '/api/v1/things',
        done: (j, _) => j is Map && (j['items'] as List).isNotEmpty,
      ),
    ),
    const MissionStep(id: 'b'),
    const MissionStep(id: 'done'),
  ],
);

const _loc = TutorialScope(
  envId: 'e1',
  kind: EnvironmentKind.tutorial,
  who: 'dev:a@x.test',
);

ProviderContainer _boot(
  FakeHttp http, {
  MemoryKvStore? kv,
  List<Mission>? missions,
  TutorialScope scope = _loc,
}) {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      kvStoreProvider.overrideWithValue(kv ?? MemoryKvStore()),
      tutorialScopeProvider.overrideWithValue(scope),
      tutorialMissionsProvider.overrideWithValue(missions ?? [_one, _two]),
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

Widget _app(ProviderContainer c, GoRouter router) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp.router(
    routerConfig: router,
    locale: const Locale('en'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) =>
        TutorialHost(router: router, child: child ?? const SizedBox()),
  ),
);

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('home')),
    ),
    GoRoute(
      path: '/tutorial',
      builder: (_, _) => const Scaffold(body: Text('chapter map')),
    ),
  ],
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<TutorialController> _startIn(
  WidgetTester tester,
  ProviderContainer c,
  String id,
) async {
  final t = c.read(tutorialProvider.notifier);
  await tester.runAsync(() => t.ready);
  await tester.runAsync(() => t.start(id));
  await _settle(tester);
  return t;
}

final _card = find.byKey(const ValueKey('tutorial-card'));
final _finished = find.byKey(const ValueKey('tutorial-finished'));
final _toNext = find.byKey(const ValueKey('tutorial-finished-next'));
final _toMap = find.byKey(const ValueKey('tutorial-finished-map'));

/// Whether a button with [key] is on screen and enabled.
bool _enabled(WidgetTester tester, Finder f) {
  if (f.evaluate().isEmpty) return false;
  final w = tester.widget(f);
  return switch (w) {
    ButtonStyleButton b => b.onPressed != null,
    _ => false,
  };
}

void main() {
  testWidgets('product assistance creates and verifies the expected motor', (
    tester,
  ) async {
    final products = <Map<String, Object>>[
      {
        'id': 'typo',
        'code': 'tut-motor',
        'product_type': 'purchased',
        'active': true,
      },
    ];
    final http = FakeHttp({
      'GET /api/v1/products': (_) => {'items': products},
      'POST /api/v1/products': (body) {
        expect((body as Map)['code'], 'TUT-MOTOR');
        expect(body['product_type'], 'purchased');
        final motor = {
          'id': 'motor',
          'code': 'TUT-MOTOR',
          'name': 'Motor',
          'product_type': 'purchased',
          'active': true,
        };
        products.add(motor);
        return motor;
      },
    });
    final c = _boot(http, missions: [productMission]);
    await tester.pumpWidget(_app(c, _router()));
    final t = await _startIn(tester, c, 'product');
    t.routeChanged('/products');
    await _settle(tester);

    final assist = find.widgetWithText(FilledButton, 'Do this step for me');
    expect(assist, findsOneWidget);
    expect(find.byKey(const ValueKey('tutorial-skip')), findsNothing);
    await tester.tap(assist);
    await _settle(tester);

    expect(t.step?.id, 'frame');
    expect(c.read(tutorialProvider).values['motorId'], 'motor');
    expect(products.map((p) => p['code']), ['tut-motor', 'TUT-MOTOR']);
    final write = http.requests.indexOf('POST /api/v1/products');
    expect(write, greaterThanOrEqualTo(1));
    expect(http.requests[write + 1], 'GET /api/v1/products');
  });

  test(
    'assistance stays on the step until the saved result is verified',
    () async {
      Map<String, Object>? motor;
      final http = FakeHttp({
        'GET /api/v1/products': (_) => {
          'items': [?motor],
        },
        'POST /api/v1/products': (_) => {
          'id': 'motor',
          'code': 'TUT-MOTOR',
          'product_type': 'purchased',
          'active': true,
        },
      });
      final c = _boot(http, missions: [productMission]);
      final t = c.read(tutorialProvider.notifier);
      await t.start('product');
      t.routeChanged('/products');
      t.skipStep();
      expect(t.step?.id, 'motor');

      // A successful response alone does not establish that later steps can find the product.
      await t.runAction();
      expect(t.step?.id, 'motor');
      expect(c.read(tutorialProvider).actionError, isNotNull);
      expect(c.read(tutorialProvider).values['motorId'], isNull);

      motor = {
        'id': 'motor',
        'code': 'TUT-MOTOR',
        'product_type': 'purchased',
        'active': true,
      };
      await t.runAction();
      expect(t.step?.id, 'frame');
      expect(c.read(tutorialProvider).actionError, isNull);
      expect(c.read(tutorialProvider).values['motorId'], 'motor');
      expect(
        http.requests.where((r) => r == 'POST /api/v1/products'),
        hasLength(1),
      );
    },
  );

  test('assistance performs no writes in a test environment', () async {
    final http = FakeHttp({
      'GET /api/v1/products': (_) => {'items': []},
    });
    final c = _boot(
      http,
      missions: [productMission],
      scope: const TutorialScope(
        envId: 'test-copy',
        kind: EnvironmentKind.test,
        who: 'dev:a@x.test',
      ),
    );
    final t = c.read(tutorialProvider.notifier);
    await t.start('product');
    t.routeChanged('/products');
    expect(t.step?.id, 'motor');
    expect(t.canAssist, isFalse);
    await t.runAction();
    expect(t.step?.id, 'motor');
    expect(
      http.requests.every((request) => request.startsWith('GET ')),
      isTrue,
    );
  });

  test(
    'going back keeps assisted writes locked until the request settles',
    () async {
      final dispatched = Completer<void>();
      final release = Completer<void>();
      Map<String, Object>? motor;
      const write = 'POST /api/v1/products';
      final http = FakeHttp({
        'GET /api/v1/products': (_) => {
          'items': [?motor],
        },
        write: (_) async {
          if (!dispatched.isCompleted) {
            dispatched.complete();
            await release.future;
          }
          return motor = {
            'id': 'motor',
            'code': 'TUT-MOTOR',
            'product_type': 'purchased',
          };
        },
      });
      final c = _boot(http, missions: [productMission]);
      final t = c.read(tutorialProvider.notifier);
      await t.start('product');
      t.routeChanged('/products');
      final pending = t.runAction();
      await dispatched.future;

      try {
        t.back();
        expect(t.step?.id, 'open');
        t.next();
        expect(t.step?.id, 'motor');
        await t.runAction();
        expect(
          http.requests.where((request) => request == write),
          hasLength(1),
        );
        expect(c.read(tutorialProvider).actionBusy, isTrue);
      } finally {
        release.complete();
        await pending;
      }

      expect(
        t.step?.id,
        'motor',
        reason: 'the original action lost step ownership',
      );
      expect(c.read(tutorialProvider).actionBusy, isFalse);
      await t.runAction();
      expect(t.step?.id, 'frame');
      expect(http.requests.where((request) => request == write), hasLength(1));
    },
  );

  group('narrator semantics', () {
    testWidgets(
      'the running narrator comes last in the reading order of the semantics tree',
      (tester) async {
        final handle = tester.ensureSemantics();
        final c = _boot(FakeHttp({}));
        await tester.pumpWidget(_app(c, _router()));
        await _startIn(tester, c, 'one');
        expect(_card, findsOneWidget);
        // Without an explicit sort key the card's small node is interleaved by position with the nodes of
        // dialogs and suggestion lists; when a list opens the order changes and the web engine moves the
        // DOM node of the focused text field, which drops its focus and closes the list.
        SemanticsNode? node = tester.getSemantics(_card);
        SemanticsSortKey? key;
        while (node != null && key == null) {
          key = node.sortKey;
          node = node.parent;
        }
        expect(key, isA<OrdinalSortKey>());
        expect((key! as OrdinalSortKey).order, greaterThan(100));
        handle.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('chapter completion card', () {
    for (final last in [false, true]) {
      testWidgets(
        'on a 400x300 window at text scale 2.0 the ${last ? 'last' : 'first'} chapter card has no overflow and tappable buttons',
        (tester) async {
          tester.view.physicalSize = const Size(400, 300);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final c = _boot(FakeHttp({}));
          await tester.pumpWidget(_app(c, _router()));
          final t = await _startIn(tester, c, 'one');
          t.next();
          t.next();
          await _settle(tester);
          if (last) {
            await tester.tap(_toNext);
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await _settle(tester);
            t.next();
            t.next();
            t.next();
            await _settle(tester);
          }
          expect(_finished, findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(_toNext, last ? findsNothing : findsOneWidget);
          expect(_toMap.hitTestable(), findsOneWidget);
          if (!last) expect(_toNext.hitTestable(), findsOneWidget);
          await tester.tap(_toMap);
          await _settle(tester);
          expect(_finished, findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'Next on the last step completes the chapter and shows the card',
      (tester) async {
        final c = _boot(FakeHttp({}));
        await tester.pumpWidget(_app(c, _router()));
        await _startIn(tester, c, 'one');
        await tester.tap(find.byKey(const ValueKey('tutorial-next')));
        await _settle(tester);
        expect(find.byKey(const ValueKey('tutorial-next')), findsOneWidget);
        expect(c.read(tutorialProvider).completed, isEmpty);

        await tester.tap(find.byKey(const ValueKey('tutorial-next')));
        await _settle(tester);

        expect(c.read(tutorialProvider).completed, {'one'});
        expect(c.read(tutorialProvider).activeId, isNull);
        expect(_card, findsNothing);
        expect(_finished, findsOneWidget);
        // The title carries the chapter's name (the test chapter has no text: its key shows).
        expect(
          find.textContaining('Chapter tutOneTitle complete'),
          findsOneWidget,
        );
        expect(_enabled(tester, _toNext), isTrue);
        expect(_enabled(tester, _toMap), isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Start next chapter starts chapter two at its first step and probes',
      (tester) async {
        final http = FakeHttp({
          'GET /api/v1/things': (_) => {'items': []},
        });
        final c = _boot(http);
        await tester.pumpWidget(_app(c, _router()));
        final t = await _startIn(tester, c, 'one');
        t.next();
        t.next();
        await _settle(tester);
        expect(http.requests, isEmpty);

        await tester.tap(_toNext);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await _settle(tester);

        final s = c.read(tutorialProvider);
        expect(s.activeId, 'two');
        expect(s.stepIndex, 0);
        expect(s.finishedId, isNull);
        expect(_finished, findsNothing);
        expect(_card, findsOneWidget);
        expect(http.requests, contains('GET /api/v1/things'));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'a satisfied needs probe lets chapter two skip its first step',
      (tester) async {
        final http = FakeHttp({
          'GET /api/v1/things': (_) => {
            'items': [
              {'id': 1},
            ],
          },
        });
        final c = _boot(http);
        await tester.pumpWidget(_app(c, _router()));
        final t = await _startIn(tester, c, 'one');
        t.next();
        t.next();
        await _settle(tester);
        await tester.tap(_toNext);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await _settle(tester);
        expect(c.read(tutorialProvider).activeId, 'two');
        expect(c.read(tutorialProvider).stepIndex, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('Back to chapter map goes to /tutorial and keeps progress', (
      tester,
    ) async {
      final router = _router();
      final c = _boot(FakeHttp({}));
      await tester.pumpWidget(_app(c, router));
      final t = await _startIn(tester, c, 'one');
      t.next();
      t.next();
      await _settle(tester);

      await tester.tap(_toMap);
      await _settle(tester);

      expect(find.text('chapter map'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.toString(), '/tutorial');
      final s = c.read(tutorialProvider);
      expect(s.completed, {'one'});
      expect(s.activeId, isNull);
      expect(s.finishedId, isNull);
      expect(_finished, findsNothing);
      // Leaving the map again does not bring the card back.
      router.go('/');
      await _settle(tester);
      expect(_finished, findsNothing);
      expect(c.read(tutorialProvider).completed, {'one'});
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the last chapter offers only the way back to the map', (
      tester,
    ) async {
      final c = _boot(FakeHttp({}));
      await tester.pumpWidget(_app(c, _router()));
      final t = await _startIn(tester, c, 'one');
      t.next();
      t.next();
      await _settle(tester);
      await tester.tap(_toNext);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
      expect(c.read(tutorialProvider).activeId, 'two');
      // Chapter two: its probe finds nothing; go to the end with Next.
      t.next();
      t.next();
      t.next();
      await _settle(tester);

      expect(c.read(tutorialProvider).completed, {'one', 'two'});
      expect(_finished, findsOneWidget);
      expect(_toNext, findsNothing);
      expect(_enabled(tester, _toMap), isTrue);
      expect(find.textContaining('last chapter'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('a restart on a finished chapter comes back without a card', () async {
      final kv = MemoryKvStore();
      final c1 = _boot(FakeHttp({}), kv: kv);
      final t1 = c1.read(tutorialProvider.notifier);
      await t1.ready;
      await t1.start('one');
      t1.next();
      t1.next();
      expect(c1.read(tutorialProvider).finishedId, 'one');

      final c2 = _boot(FakeHttp({}), kv: kv);
      final t2 = c2.read(tutorialProvider.notifier);
      await t2.ready;
      final s = c2.read(tutorialProvider);
      expect(s.completed, {'one'});
      expect(s.finishedId, isNull);
      expect(s.activeId, isNull);
      expect(t2.currentChapter?.id, 'two');
      // Resuming the finished chapter replays it from the start.
      expect(await t2.resume('one'), StartResult.started);
      expect(c2.read(tutorialProvider).stepIndex, 0);
      expect(c2.read(tutorialProvider).running, isTrue);
    });

    test(
      'a stored place past the end of a chapter is clamped, not a dead card',
      () async {
        final kv = MemoryKvStore();
        await kv.set(
          _loc.storageKey,
          jsonEncode({
            'completed': <String>[],
            'active': 'one',
            'step': 7,
            'progress': {'one': 7},
          }),
        );
        final c = _boot(FakeHttp({}), kv: kv);
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        expect(t.step, isNotNull);
        expect(c.read(tutorialProvider).stepIndex, 1);
        expect(c.read(tutorialProvider).paused, isTrue);
      },
    );

    testWidgets(
      'every state of the card offers an enabled action (all real chapters)',
      (tester) async {
        final c = _boot(FakeHttp({}), missions: allMissions);
        await tester.pumpWidget(_app(c, _router()));
        final t = c.read(tutorialProvider.notifier);
        await tester.runAsync(() => t.ready);
        for (var i = 0; i < allMissions.length; i++) {
          final m = allMissions[i];
          await tester.runAsync(() => t.start(m.id));
          await _settle(tester);
          for (var k = 0; k < m.steps.length; k++) {
            final where = '${m.id}/${m.steps[k].id}';
            expect(c.read(tutorialProvider).stepIndex, k, reason: where);
            expect(_card, findsOneWidget, reason: where);
            final actions = [
              'tutorial-next',
              'tutorial-action',
              'tutorial-skip',
              'tutorial-pause',
            ];
            expect(
              actions.any((k) => _enabled(tester, find.byKey(ValueKey(k)))),
              isTrue,
              reason: 'no way forward on $where',
            );
            expect(
              _enabled(tester, find.byKey(const ValueKey('tutorial-pause'))),
              isTrue,
              reason: where,
            );
            t.next();
            await _settle(tester);
          }
          expect(c.read(tutorialProvider).completed, contains(m.id));
          expect(_finished, findsOneWidget, reason: m.id);
          expect(_enabled(tester, _toMap), isTrue, reason: m.id);
          expect(
            _enabled(tester, _toNext),
            i < allMissions.length - 1,
            reason: m.id,
          );
          // Paused is a state too: the pill resumes.
          if (i == 0) {
            await tester.runAsync(() => t.start(m.id));
            await _settle(tester);
            t.pause();
            await _settle(tester);
            expect(
              _enabled(tester, find.byKey(const ValueKey('tutorial-resume'))),
              isTrue,
            );
            await tester.runAsync(() => t.resume());
            await _settle(tester);
            while (c.read(tutorialProvider).activeId != null) {
              t.next();
            }
            await _settle(tester);
          }
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
