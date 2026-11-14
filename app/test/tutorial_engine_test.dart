import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/environments.dart';
import 'package:tradocraft_app/app/session.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/tutorial/api_events.dart';
import 'package:tradocraft_app/features/tutorial/chapter_map_page.dart';
import 'package:tradocraft_app/features/tutorial/controller.dart';
import 'package:tradocraft_app/features/tutorial/model.dart';
import 'package:tradocraft_app/features/tutorial/overlay.dart';
import 'package:tradocraft_app/features/tutorial/targets.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

/// A small mission that uses every kind of completion.
final demo = Mission(
  id: 'demo',
  steps: [
    const MissionStep(id: 'a'),
    MissionStep(
      id: 'b',
      completion: OnApi(
        'POST',
        '/things',
        predicate: (j, _) => j is Map && j['kind'] == 'x',
      ),
      capture: (j) => {'thingId': '${(j as Map)['id']}'},
    ),
    const MissionStep(
      id: 'c',
      route: '/things/{thingId}',
      targets: ['nowhere'],
      completion: OnRoute('/things/{thingId}'),
    ),
    MissionStep(
      id: 'd',
      probe: Probe(
        '/api/v1/things',
        query: const {'q': 'z'},
        done: (j, _) => j is Map && (j['items'] as List).isNotEmpty,
      ),
    ),
    const MissionStep(id: 'e'),
  ],
);

const other = Mission(
  id: 'other',
  steps: [MissionStep(id: 'a')],
);

TutorialScope scope(
  EnvironmentKind kind, {
  String env = 'e1',
  String who = 'dev:a@x.test',
}) => TutorialScope(envId: env, kind: kind, who: who);

ProviderContainer boot({
  TutorialScope? sc,
  MemoryKvStore? kv,
  FakeHttp? http,
  List<Mission>? missions,
}) {
  final h = http ?? FakeHttp({});
  final c = ProviderContainer(
    overrides: [
      kvStoreProvider.overrideWithValue(kv ?? MemoryKvStore()),
      tutorialScopeProvider.overrideWithValue(
        sc ?? scope(EnvironmentKind.test),
      ),
      tutorialMissionsProvider.overrideWithValue(missions ?? [demo, other]),
      // The real interceptor on a fake server: events come from real calls.
      dioProvider.overrideWith((ref) {
        final d = fakeDio(h);
        d.interceptors.add(ApiEventInterceptor(ref.read(apiEventBusProvider)));
        return d;
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<TutorialController> started(
  ProviderContainer c, [
  String id = 'demo',
]) async {
  final t = c.read(tutorialProvider.notifier);
  await t.ready;
  expect(await t.start(id), StartResult.started);
  return t;
}

void main() {
  group('step progression', () {
    test('next, back, skip step, skip chapter, pause, resume, replay', () async {
      final c = boot();
      final t = await started(c);
      expect(c.read(tutorialProvider).stepIndex, 0);
      t.next();
      expect(c.read(tutorialProvider).stepIndex, 1);
      t.back();
      expect(c.read(tutorialProvider).stepIndex, 0);
      t.back(); // already at the first step
      expect(c.read(tutorialProvider).stepIndex, 0);
      t.next();
      t.skipStep();
      expect(c.read(tutorialProvider).stepIndex, 2);

      t.pause();
      expect(c.read(tutorialProvider).running, isFalse);
      expect(c.read(apiEventBusProvider).active, isFalse);
      t.next(); // ignored while paused
      expect(c.read(tutorialProvider).stepIndex, 2);
      expect(await t.resume(), StartResult.started);
      expect(c.read(tutorialProvider).running, isTrue);
      expect(c.read(tutorialProvider).stepIndex, 2);

      await t.skipChapter();
      var s = c.read(tutorialProvider);
      expect(s.activeId, isNull);
      expect(s.skipped, {'demo'});
      expect(s.isDone('demo'), isTrue);
      expect(c.read(apiEventBusProvider).active, isFalse);

      // A chapter that is done or skipped can be replayed from its first step.
      expect(await t.start('demo'), StartResult.started);
      s = c.read(tutorialProvider);
      expect(s.activeId, 'demo');
      expect(s.stepIndex, 0);
    });

    test('a chapter is locked until the ones before it are done', () async {
      final c = boot();
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      expect(t.isUnlocked(0), isTrue);
      expect(t.isUnlocked(1), isFalse);
      expect(await t.start('other'), StartResult.locked);
      expect(await t.start('missing'), StartResult.unavailable);
      await t.skipChapter('demo');
      expect(t.isUnlocked(1), isTrue);
      expect(t.currentChapter?.id, 'other');
    });

    test('finishing the last step completes the chapter', () async {
      final c = boot(missions: [other]);
      final t = await started(c, 'other');
      t.next();
      final s = c.read(tutorialProvider);
      expect(s.completed, {'other'});
      expect(s.activeId, isNull);
    });
  });

  group('completion', () {
    test('an API event finishes the step, captures a value, and a route finishes the next', () async {
      final http = FakeHttp({
        'POST /api/v1/things': (b) => {'id': 't1', 'kind': (b as Map)['kind']},
      });
      final c = boot(http: http);
      final t = await started(c);
      final dio = c.read(dioProvider);
      t.next(); // at step b
      expect(c.read(apiEventBusProvider).active, isTrue);

      await dio.post<Object?>('/api/v1/things', data: {'kind': 'y'});
      expect(
        c.read(tutorialProvider).stepIndex,
        1,
        reason: 'predicate says no',
      );

      await dio.post<Object?>('/api/v1/things', data: {'kind': 'x'});
      var s = c.read(tutorialProvider);
      expect(s.stepIndex, 2);
      expect(s.values['thingId'], 't1');

      // The deep link of the next step uses the captured id.
      expect(s.context.resolve(demo.steps[2].route!), '/things/t1');
      t.routeChanged('/things/other');
      expect(c.read(tutorialProvider).stepIndex, 2);
      t.routeChanged('/things/t1');
      s = c.read(tutorialProvider);
      expect(s.stepIndex, 3);
    });

    test(
      'a failed call does not finish a step; nothing is seen while paused',
      () async {
        final http = FakeHttp({
          'POST /api/v1/things': (_) => const FakeStatus(409, {'error': 'x'}),
        });
        final c = boot(http: http);
        final t = await started(c);
        t.next();
        final dio = c.read(dioProvider);
        await expectLater(
          dio.post<Object?>('/api/v1/things', data: {'kind': 'x'}),
          throwsA(isA<DioException>()),
        );
        expect(c.read(tutorialProvider).stepIndex, 1);
        t.pause();
        http.routes['POST /api/v1/things'] = (_) => {'id': 't2'};
        await dio.post<Object?>('/api/v1/things', data: {'kind': 'x'});
        expect(c.read(tutorialProvider).stepIndex, 1);
      },
    );

    test('the bus keeps nothing while no mission runs', () async {
      final bus = ApiEventBus();
      final seen = <ApiEvent>[];
      bus.stream.listen(seen.add);
      bus.emit(const ApiEvent('GET', '/x', 200, null));
      expect(seen, isEmpty);
      bus.active = true;
      bus.emit(const ApiEvent('GET', '/x', 200, null));
      expect(seen, hasLength(1));
      bus.dispose();
    });

    test(
      'a probe that says done finishes the step; back does not probe again',
      () async {
        final http = FakeHttp({
          'GET /api/v1/things': (_) => {
            'items': [
              {'id': 't9'},
            ],
          },
        });
        final c = boot(http: http);
        final t = await started(c);
        // Jump to step d through steps that need nothing from the server.
        t.next();
        t.skipStep();
        t.skipStep();
        await pumpEventQueue();
        expect(http.requests, contains('GET /api/v1/things'));
        expect(
          c.read(tutorialProvider).stepIndex,
          4,
          reason: 'probe finished d',
        );
        t.back();
        await pumpEventQueue();
        expect(
          c.read(tutorialProvider).stepIndex,
          3,
          reason: 'back does not re-run the probe',
        );
      },
    );

    test(
      'an already satisfied location finishes a route step at once',
      () async {
        final http = FakeHttp({
          'POST /api/v1/things': (b) => {
            'id': 't7',
            'kind': (b as Map)['kind'],
          },
        });
        final c = boot(http: http);
        final t = await started(c);
        t.routeChanged('/things/t7');
        t.next(); // at step b
        await c
            .read(dioProvider)
            .post<Object?>('/api/v1/things', data: {'kind': 'x'});
        // Step c (the route step) was entered with the location already showing /things/t7.
        expect(c.read(tutorialProvider).values['thingId'], 't7');
        expect(c.read(tutorialProvider).stepIndex, 3);
      },
    );

    test('events sent as another session do not finish a step', () async {
      final c = boot();
      final t = await started(c);
      t.next();
      final bus = c.read(apiEventBusProvider);
      bus.emit(
        const ApiEvent('POST', '/things', 200, {
          'id': 'x',
          'kind': 'x',
        }, scope: 'other|session'),
      );
      expect(c.read(tutorialProvider).stepIndex, 1);
      bus.emit(
        ApiEvent('POST', '/things', 200, const {
          'id': 'x',
          'kind': 'x',
        }, scope: tutorialSessionId(c.read(sessionProvider))),
      );
      expect(c.read(tutorialProvider).stepIndex, 2);
    });

    test(
      'the interceptor stamps requests with the session it belongs to',
      () async {
        final http = FakeHttp({
          'POST /api/v1/things': (_) => {'id': 'a'},
        });
        final bus = ApiEventBus()..active = true;
        final seen = <ApiEvent>[];
        bus.stream.listen(seen.add);
        final d = fakeDio(http)
          ..interceptors.add(ApiEventInterceptor(bus, scope: 's1'));
        await d.post<Object?>('/api/v1/things', data: {});
        expect(seen.single.scope, 's1');
        bus.dispose();
      },
    );

    test('a token session is scoped by the token subject and the company', () {
      String jwt(String sub) =>
          'h.${base64Url.encode(utf8.encode(jsonEncode({'sub': sub})))}.s';
      expect(tokenSubject(jwt('user-1')), 'user-1');
      expect(tokenSubject('not-a-jwt'), isNull);
      final c = ProviderContainer(
        overrides: [
          initialSessionProvider.overrideWithValue(
            Session(
              serverUrl: 'http://x',
              accessToken: jwt('u1'),
              companyId: 'co',
            ),
          ),
          initialEnvironmentsProvider.overrideWithValue(
            EnvironmentStore.fromSession(const Session(serverUrl: 'http://x')),
          ),
          environmentProbeProvider.overrideWithValue(
            (_) async => throw Exception('x'),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(tutorialScopeProvider).who, 'token:u1:co');
    });

    test('skipChapter waits for the stored progress to load', () async {
      final kv = MemoryKvStore();
      final first = await started(boot(kv: kv));
      await first.skipChapter();
      await pumpEventQueue();
      final c = boot(kv: kv);
      final t = c.read(tutorialProvider.notifier);
      await t.skipChapter('other'); // no wait for ready by the caller
      final s = c.read(tutorialProvider);
      expect(s.skipped, containsAll(['demo', 'other']));
    });

    test(
      'the registry gives back the earlier target when the newest goes away',
      () {
        final r = TutorialTargetRegistry();
        final a = GlobalKey(), b = GlobalKey();
        r.register('x', a);
        r.register('x', b);
        expect(r['x'], b);
        r.unregister('x', b);
        expect(r['x'], a);
        r.unregister('x', a);
        expect(r['x'], isNull);
      },
    );

    test('an action step runs its code and captures the result', () async {
      final act = Mission(
        id: 'act',
        steps: [
          MissionStep(
            id: 'go',
            completion: ActionCompletion((host) async => {'sent': 'yes'}),
          ),
          const MissionStep(id: 'end'),
        ],
      );
      final c = boot(missions: [act]);
      final t = await started(c, 'act');
      await t.runAction();
      final s = c.read(tutorialProvider);
      expect(s.stepIndex, 1);
      expect(s.values['sent'], 'yes');
    });
  });

  group('environment', () {
    test('refuses to run on live and runs on test and tutorial', () async {
      for (final kind in EnvironmentKind.values) {
        final c = boot(sc: scope(kind));
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        final r = await t.start('demo');
        if (kind == EnvironmentKind.live) {
          expect(r, StartResult.refusedLive);
          expect(c.read(tutorialProvider).activeId, isNull);
          expect(c.read(apiEventBusProvider).active, isFalse);
        } else {
          expect(r, StartResult.started, reason: kind.name);
        }
      }
    });

    test('nobody signed in: nothing starts', () async {
      final c = boot(sc: scope(EnvironmentKind.test, who: ''));
      final t = c.read(tutorialProvider.notifier);
      await t.ready;
      expect(await t.start('demo'), StartResult.unavailable);
    });
  });

  group('persistence', () {
    test('progress is stored per environment and user, and a restart comes back paused', () async {
      final kv = MemoryKvStore();
      final a = boot(kv: kv);
      final ta = await started(a);
      ta.next();
      ta.next();
      await pumpEventQueue();

      // Another environment and another user see nothing.
      for (final other in [
        scope(EnvironmentKind.test, env: 'e2'),
        scope(EnvironmentKind.test, who: 'dev:b@x.test'),
      ]) {
        final c = boot(kv: kv, sc: other);
        await c.read(tutorialProvider.notifier).ready;
        expect(c.read(tutorialProvider).activeId, isNull);
        expect(c.read(tutorialProvider).loaded, isTrue);
      }

      // The same one after a restart: its place is kept but it does not run by itself.
      final again = boot(kv: kv);
      final t = again.read(tutorialProvider.notifier);
      await t.ready;
      var s = again.read(tutorialProvider);
      expect(s.activeId, 'demo');
      expect(s.stepIndex, 2);
      expect(s.paused, isTrue);
      expect(s.running, isFalse);
      expect(await t.resume(), StartResult.started);
      s = again.read(tutorialProvider);
      expect(s.running, isTrue);
      expect(s.stepIndex, 2);
    });

    test('unreadable stored data is ignored', () async {
      final kv = MemoryKvStore();
      final key = scope(EnvironmentKind.test).storageKey;
      for (final junk in ['{nope', '[]', '{"completed": 5, "active": 7}']) {
        kv.data[key] = junk;
        final c = boot(kv: kv);
        final t = c.read(tutorialProvider.notifier);
        await t.ready;
        final s = c.read(tutorialProvider);
        expect(s.loaded, isTrue, reason: junk);
        expect(s.completed, isEmpty);
        expect(s.activeId, isNull);
        expect(await t.start('demo'), StartResult.started);
      }
    });

    test('stored progress on a live environment never runs', () async {
      final kv = MemoryKvStore();
      final t = await started(boot(kv: kv));
      t.next();
      await pumpEventQueue();
      final live = boot(kv: kv, sc: scope(EnvironmentKind.live));
      final lt = live.read(tutorialProvider.notifier);
      await lt.ready;
      expect(live.read(tutorialProvider).running, isFalse);
      expect(live.read(tutorialProvider).activeId, isNull);
      expect(await lt.resume('demo'), StartResult.refusedLive);
    });
  });

  group('spotlight', () {
    test('the scrim has a rounded hole where the target is', () {
      const hole = Rect.fromLTWH(100, 80, 120, 40);
      const painter = SpotlightPainter(
        hole: hole,
        scrim: Colors.black54,
        ring: Colors.white,
      );
      const size = Size(800, 600);
      final path = painter.scrimPath(size);
      expect(
        path.contains(hole.center),
        isFalse,
        reason: 'taps see the target',
      );
      expect(path.contains(const Offset(10, 10)), isTrue);
      expect(path.contains(const Offset(500, 500)), isTrue);
      // Rounded corners: the very corner of the rectangle is dimmed.
      expect(path.contains(hole.topLeft + const Offset(0.5, 0.5)), isTrue);
      expect(
        painter.shouldRepaint(
          const SpotlightPainter(
            hole: Rect.fromLTWH(0, 0, 1, 1),
            scrim: Colors.black54,
            ring: Colors.white,
          ),
        ),
        isTrue,
      );
    });

    testWidgets('the overlay cuts out the registered target', (tester) async {
      final c = boot(missions: [spot]);
      await tester.pumpWidget(_host(c, targets: true));
      final t = c.read(tutorialProvider.notifier);
      await tester.runAsync(() => t.ready);
      await tester.runAsync(() => t.start('spot'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final rect = tester.getRect(find.byKey(const ValueKey('the-button')));
      final scrim = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('tutorial-scrim')),
      );
      final painter = scrim.painter! as SpotlightPainter;
      expect(painter.hole, rect.inflate(SpotlightPainter.padding));
      expect(find.byKey(const ValueKey('tutorial-card')), findsOneWidget);
      // The card names the step; Next and Pause are there and reachable.
      expect(find.text('MissionStep 1 of 1'), findsNothing);
      expect(find.byKey(const ValueKey('tutorial-pause')), findsOneWidget);

      // Taps still reach the target through the hole.
      await tester.tap(find.byKey(const ValueKey('the-button')));
      expect(_tapped, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'a missing target falls back to a text-only card with "Take me there"',
      (tester) async {
        final c = boot(missions: [spot]);
        await tester.pumpWidget(_host(c, targets: false));
        final t = c.read(tutorialProvider.notifier);
        await tester.runAsync(() => t.ready);
        await tester.runAsync(() => t.start('spot'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const ValueKey('tutorial-scrim')), findsNothing);
        expect(find.byKey(const ValueKey('tutorial-card')), findsOneWidget);
        expect(find.byKey(const ValueKey('tutorial-take-me')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('tutorial-take-me')));
        await tester.pumpAndSettle();
        expect(find.text('far page'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a target under a dialog counts as missing', (tester) async {
      final c = boot(missions: [spot]);
      await tester.pumpWidget(_host(c, targets: true));
      final t = c.read(tutorialProvider.notifier);
      await tester.runAsync(() => t.ready);
      await tester.runAsync(() => t.start('spot'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('tutorial-scrim')), findsOneWidget);

      final nav = tester.element(find.byKey(const ValueKey('the-button')));
      showDialog<void>(
        context: nav,
        builder: (_) =>
            const AlertDialog(content: SizedBox(width: 3000, height: 3000)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('tutorial-scrim')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('card and location', () {
    testWidgets(
      'the narrator card scrolls on a short screen and keeps its buttons',
      (tester) async {
        tester.view.physicalSize = const Size(400, 300);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = boot(missions: [spot]);
        await tester.pumpWidget(_host(c, targets: false));
        final t = c.read(tutorialProvider.notifier);
        await tester.runAsync(() => t.ready);
        await tester.runAsync(() => t.start('spot'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsWidgets);
        expect(find.byKey(const ValueKey('tutorial-pause')), findsOneWidget);
        final card = tester.getRect(
          find.byKey(const ValueKey('tutorial-card')),
        );
        expect(card.height, lessThanOrEqualTo(300));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a focused workspace tab reports its own location', (
      tester,
    ) async {
      final c = boot(missions: [loc]);
      await tester.pumpWidget(_host(c, targets: false));
      final t = c.read(tutorialProvider.notifier);
      await tester.runAsync(() => t.ready);
      await tester.runAsync(() => t.start('loc'));
      await tester.pump();
      c.read(workspaceProvider.notifier).open('/things/t1');
      await tester.pump();
      await tester.pump();
      expect(c.read(tutorialProvider).location, '/things/t1');
      expect(c.read(tutorialProvider).completed, {'loc'});
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('chapter map', () {
    testWidgets('refuses on live and offers to switch or add an environment', (
      tester,
    ) async {
      final c = _wired(EnvironmentKind.live);
      await tester.pumpWidget(_mapApp(c));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tutorial-live-refusal')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tutorial-chapter-demo')), findsNothing);
      expect(find.byKey(const ValueKey('env-banner-live')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tutorial-switch-env')));
      await tester.pumpAndSettle();
      expect(find.text('Switch environment'), findsWidgets);
      expect(find.byKey(const ValueKey('env-add')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on a test environment: locked, start, skip and replay', (
      tester,
    ) async {
      final c = _wired(EnvironmentKind.test);
      await tester.pumpWidget(_mapApp(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('env-banner-test')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tutorial-chapter-demo')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tutorial-chapter-other')),
          matching: find.text('Locked'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tutorial-start-other')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tutorial-skip-demo')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tutorial-chapter-demo')),
          matching: find.text('Skipped'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tutorial-start-other')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tutorial-replay-demo')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('tutorial-replay-demo')));
      await tester.pumpAndSettle();
      expect(c.read(tutorialProvider).activeId, 'demo');
      expect(
        find.text('far page'),
        findsOneWidget,
        reason: 'went back to the app',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'the offer on first sign-in appears in a tutorial environment only',
      (tester) async {
        for (final kind in [EnvironmentKind.tutorial, EnvironmentKind.test]) {
          final c = _wired(kind);
          await tester.pumpWidget(_hostApp(c));
          await tester.runAsync(() => c.read(tutorialProvider.notifier).ready);
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.byKey(const ValueKey('tutorial-offer')),
            kind == EnvironmentKind.tutorial ? findsOneWidget : findsNothing,
            reason: kind.name,
          );
          if (kind == EnvironmentKind.tutorial) {
            await tester.tap(
              find.byKey(const ValueKey('tutorial-offer-start')),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(c.read(tutorialProvider).activeId, 'demo');
            expect(find.byKey(const ValueKey('tutorial-offer')), findsNothing);
          }
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  });
}

int _tapped = 0;

/// A mission finished by showing /things/t1.
const loc = Mission(
  id: 'loc',
  steps: [MissionStep(id: 'a', completion: OnRoute('/things/t1'))],
);

/// A one-step mission that points at 'the-button' and has a route to a far page.
const spot = Mission(
  id: 'spot',
  steps: [
    MissionStep(id: 'a', targets: ['the-button'], route: '/far'),
  ],
);

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: Center(
          child: TutorialTarget(
            id: 'the-button',
            child: ElevatedButton(
              key: const ValueKey('the-button'),
              onPressed: () => _tapped++,
              child: const Text('Press'),
            ),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/far',
      builder: (_, _) => const Scaffold(body: Text('far page')),
    ),
  ],
);

/// The app with the tutorial host; [targets] false leaves the target out of the page.
Widget _host(ProviderContainer c, {required bool targets}) {
  _tapped = 0;
  final router = targets
      ? _router()
      : GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('home')),
            ),
            GoRoute(
              path: '/far',
              builder: (_, _) => const Scaffold(body: Text('far page')),
            ),
          ],
        );
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          TutorialHost(router: router, child: child ?? const SizedBox()),
    ),
  );
}

/// A container with the real environment and session providers (kind [kind]).
ProviderContainer _wired(EnvironmentKind kind) {
  const url = 'http://localhost:8081';
  final env = AppEnvironment(
    id: 'env-1',
    name: 'Practice',
    kind: kind,
    serverUrl: url,
    devUser: 'admin@example.test',
    companyId: 'co',
  );
  final state = EnvironmentsState(items: [env], activeId: 'env-1');
  final c = ProviderContainer(
    overrides: [
      kvStoreProvider.overrideWithValue(MemoryKvStore()),
      initialEnvironmentsProvider.overrideWithValue(state),
      initialSessionProvider.overrideWithValue(env.session),
      environmentProbeProvider.overrideWithValue(
        (_) async => throw Exception('offline'),
      ),
      tutorialMissionsProvider.overrideWithValue([demo, other]),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _mapApp(ProviderContainer c) {
  final router = GoRouter(
    initialLocation: '/far',
    routes: [
      GoRoute(
        path: '/far',
        builder: (_, _) => const Scaffold(body: Text('far page')),
      ),
      GoRoute(
        path: '/products',
        builder: (_, _) => const Scaffold(body: Text('far page')),
      ),
      GoRoute(path: '/tutorial', builder: (_, _) => const TutorialMapPage()),
    ],
  );
  router.push('/tutorial');
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

Widget _hostApp(ProviderContainer c) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          TutorialHost(router: router, child: child ?? const SizedBox()),
    ),
  );
}
