import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/session.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/todo/object_todos_button.dart';
import 'package:tradocraft_app/features/todo/todo_page.dart';
import 'package:tradocraft_app/features/todo/todo_repository.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/load_failed.dart';

import 'fake_http.dart';

const _counts = 'GET /api/v1/todo/items/counts';

Map<String, Object?> _item(
  String id,
  String title, {
  String? due,
  String? linkKind,
  String? linkId,
}) => {
  'id': id,
  'parent_id': null,
  'position': 0,
  'title': title,
  'notes': '',
  'owner_id': 'u1',
  'owner_name': 'Me',
  'assignee_id': null,
  'assignee_name': null,
  'created_by': 'u1',
  'mine': true,
  'due_date': due,
  'done': false,
  'done_at': null,
  'done_by': null,
  'link_kind': linkKind,
  'link_id': linkId,
  'link_label': linkKind == null ? null : 'Linked',
  'link_location': null,
  'client_id': null,
  'created_at': '2027-02-02T09:00:00Z',
  'updated_at': '2027-02-02T09:00:00Z',
};

String _day(int offset) {
  final d = DateTime.now().add(Duration(days: offset));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Lets chained requests (me, then the list) finish: Dio answers through timers, not frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

const _signedIn = Session(serverUrl: 'http://test', devUser: 'me@example.com');

void main() {
  late FakeHttp http;
  late ProviderContainer container;
  var counts = <String, Object?>{'open': 0, 'overdue': 0, 'due_today': 0};

  int countCalls() => http.requests.where((r) => r == _counts).length;
  Finder badge() => find.byKey(const ValueKey('todo-nav-badge'));

  ColorScheme scheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

  /// The shell with the to-do page, at [width] logical pixels.
  Future<void> pumpShell(
    WidgetTester tester, {
    double width = 1400,
    List<String> perms = const ['todo.use'],
    Map<String, Object? Function(Object?)> routes = const {},
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      _counts: (_) => counts,
      'GET /api/v1/todo/items': (_) => <Object?>[],
      'GET /api/v1/todo/settings': (_) => {'email_reminders': true},
      'POST /api/v1/todo/items/a/complete': (_) => _item('a', 'x'),
      ...routes,
    });
    container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
        initialSessionProvider.overrideWithValue(_signedIn),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/todo',
      routes: [
        ShellRoute(
          builder: (c, s, child) =>
              AppShell(location: s.matchedLocation, child: child),
          routes: [
            GoRoute(path: '/todo', builder: (_, _) => const TodoPage()),
            GoRoute(path: '/orders', builder: (_, _) => const Text('ORDERS')),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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

  setUp(() {
    counts = {'open': 0, 'overdue': 0, 'due_today': 0};
  });

  group('shell badge', () {
    testWidgets(
      'rail: the number of open items, neutral until one is overdue',
      (tester) async {
        counts = {'open': 3, 'overdue': 0, 'due_today': 1};
        await pumpShell(tester);
        expect(badge(), findsOneWidget);
        expect(
          find.descendant(of: badge(), matching: find.text('3')),
          findsOneWidget,
        );
        expect(
          tester.widget<Badge>(badge()).backgroundColor,
          scheme(tester).primary,
        );
      },
    );

    testWidgets('rail: red when at least one item is overdue', (tester) async {
      counts = {'open': 5, 'overdue': 2, 'due_today': 0};
      await pumpShell(tester);
      expect(
        find.descendant(of: badge(), matching: find.text('5')),
        findsOneWidget,
      );
      expect(
        tester.widget<Badge>(badge()).backgroundColor,
        scheme(tester).error,
      );
    });

    testWidgets('narrow bottom bar shows the same badge', (tester) async {
      counts = {'open': 4, 'overdue': 1, 'due_today': 0};
      await pumpShell(
        tester,
        width: 500,
        perms: const ['todo.use', 'orders.read'],
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byKey(const ValueKey('todo-nav-badge')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: badge(), matching: find.text('4')),
        findsOneWidget,
      );
      expect(
        tester.widget<Badge>(badge()).backgroundColor,
        scheme(tester).error,
      );
    });

    testWidgets('hidden at zero', (tester) async {
      await pumpShell(tester);
      expect(badge(), findsNothing);
      expect(countCalls(), 1);
    });

    testWidgets('hidden, and never requested, without todo.use', (
      tester,
    ) async {
      counts = {'open': 3, 'overdue': 0, 'due_today': 0};
      await pumpShell(
        tester,
        perms: const ['orders.read'],
        routes: {'GET /api/v1/todo/items': (_) => FakeStatus(403, {})},
      );
      expect(badge(), findsNothing);
      expect(countCalls(), 0);
      await tester.pump(const Duration(minutes: 10));
      expect(countCalls(), 0);
    });

    testWidgets('a click on the destination goes to /todo', (tester) async {
      counts = {'open': 2, 'overdue': 0, 'due_today': 0};
      await pumpShell(tester, perms: const ['todo.use', 'orders.read']);
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(find.text('ORDERS'), findsOneWidget);
      await tester.tap(
        find.descendant(of: badge(), matching: find.byType(Icon)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TodoPage), findsOneWidget);
    });
  });

  group('freshness', () {
    testWidgets('a change made in the app refreshes the badge, bursts once', (
      tester,
    ) async {
      counts = {'open': 3, 'overdue': 0, 'due_today': 0};
      await pumpShell(tester);
      expect(countCalls(), 1);
      counts = {'open': 2, 'overdue': 0, 'due_today': 0};
      final repo = container.read(todoRepositoryProvider);
      // The calls need the test clock to finish: start them, then let time pass.
      final calls = [for (var i = 0; i < 3; i++) repo.complete('a')];
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await Future.wait(calls);
      // Not yet: the burst is debounced.
      expect(countCalls(), 1);
      await tester.pump(todoBadgeDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(countCalls(), 2);
      expect(
        find.descendant(of: badge(), matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('refreshes every few minutes in the foreground only', (
      tester,
    ) async {
      counts = {'open': 1, 'overdue': 0, 'due_today': 0};
      await pumpShell(tester);
      expect(countCalls(), 1);
      counts = {'open': 7, 'overdue': 0, 'due_today': 0};
      await tester.pump(todoBadgeInterval);
      await tester.pumpAndSettle();
      expect(countCalls(), 2);
      expect(
        find.descendant(of: badge(), matching: find.text('7')),
        findsOneWidget,
      );

      // In the background nothing is requested; coming back refreshes at once.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(todoBadgeInterval * 2);
      await tester.pumpAndSettle();
      expect(countCalls(), 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(countCalls(), 3);
    });

    testWidgets('stops when the user signs out', (tester) async {
      counts = {'open': 2, 'overdue': 0, 'due_today': 0};
      await pumpShell(tester);
      expect(badge(), findsOneWidget);
      final before = countCalls();
      await container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(badge(), findsNothing);
      await tester.pump(todoBadgeInterval * 3);
      await tester.pumpAndSettle();
      expect(countCalls(), before);
    });
  });

  group('per-record button', () {
    Future<void> pumpButton(WidgetTester tester, List<Object?> items) async {
      http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['todo.use']),
        'GET /api/v1/todo/items': (_) => items,
      });
      container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(fakeDio(http)),
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: ObjectTodosButton(kind: TodoLinkKind.order, id: 'o1'),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    Badge objectBadge(WidgetTester tester) =>
        tester.widget<Badge>(find.byKey(const ValueKey('object-todos-badge')));

    testWidgets('red when a listed item is overdue', (tester) async {
      await pumpButton(tester, [
        _item('a', 'late', due: _day(-1)),
        _item('b', 'later', due: _day(3)),
      ]);
      expect(find.text('2'), findsOneWidget);
      expect(objectBadge(tester).backgroundColor, scheme(tester).error);
    });

    testWidgets('neutral when nothing is overdue, today is not overdue', (
      tester,
    ) async {
      await pumpButton(tester, [
        _item('a', 'today', due: _day(0)),
        _item('b', 'undated'),
      ]);
      expect(objectBadge(tester).backgroundColor, scheme(tester).primary);
    });
  });

  group('not found: remove link', () {
    var linked = <Object?>[];

    Future<void> pumpMissing(
      WidgetTester tester, {
      bool notFound = true,
      List<String> perms = const ['todo.use'],
    }) async {
      http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(perms),
        'GET /api/v1/todo/items': (_) => linked,
        'PATCH /api/v1/todo/items/a': (_) {
          linked = [];
          return _item('a', 'Call');
        },
      });
      container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(fakeDio(http)),
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: LoadFailedView(
                message: 'gone',
                leaveTo: '/orders',
                notFound: notFound,
                todoKind: TodoLinkKind.order,
                todoId: 'o1',
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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
      await _settle(tester);
    }

    final button = find.byKey(const ValueKey('record-remove-todo-link'));

    testWidgets('offers the action, clears the link and goes away', (
      tester,
    ) async {
      linked = [_item('a', 'Call', linkKind: 'order', linkId: 'o1')];
      await pumpMissing(tester);
      expect(button, findsOneWidget);
      expect(find.text('Remove link from my to-dos'), findsOneWidget);
      // The lookup is by kind and id.
      final i = http.requests.indexOf('GET /api/v1/todo/items');
      expect(http.queries[i]['link_kind'], 'order');
      expect(http.queries[i]['link_id'], 'o1');

      await tester.tap(button);
      await _settle(tester);
      expect(http.bodies['PATCH /api/v1/todo/items/a'], {'clear_link': true});
      expect(button, findsNothing);
    });

    testWidgets('hidden without linked items', (tester) async {
      linked = [];
      await pumpMissing(tester);
      expect(button, findsNothing);
    });

    testWidgets('hidden when the record merely failed to load', (tester) async {
      linked = [_item('a', 'Call', linkKind: 'order', linkId: 'o1')];
      await pumpMissing(tester, notFound: false);
      expect(button, findsNothing);
      expect(http.requests, isNot(contains('GET /api/v1/todo/items')));
    });

    testWidgets('hidden, and nothing requested, without todo.use', (
      tester,
    ) async {
      linked = [_item('a', 'Call', linkKind: 'order', linkId: 'o1')];
      await pumpMissing(tester, perms: const ['orders.read']);
      expect(button, findsNothing);
      expect(http.requests, isNot(contains('GET /api/v1/todo/items')));
    });
  });

  group('reminder switch', () {
    testWidgets('shows the server value and stores a change', (tester) async {
      var on = true;
      await pumpShell(
        tester,
        routes: {
          'GET /api/v1/todo/settings': (_) => {'email_reminders': on},
          'PUT /api/v1/todo/settings': (b) {
            on = (b as Map)['email_reminders'] as bool;
            return {'email_reminders': on};
          },
        },
      );
      final sw = find.byKey(const ValueKey('todo-email-reminders'));
      expect(find.text('E-mail reminders'), findsOneWidget);
      expect(tester.widget<Switch>(sw).value, isTrue);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/todo/settings'], {
        'email_reminders': false,
      });
      expect(tester.widget<Switch>(sw).value, isFalse);
    });
  });
}
