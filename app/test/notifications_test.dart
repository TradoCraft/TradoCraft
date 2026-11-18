import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/session.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Future<(FakeHttp, GoRouter)> _shell(
  WidgetTester tester,
  List<String> perms, {
  Map<String, dynamic> counts = const {'open': 0, 'overdue': 0, 'due_today': 0},
  String? worker,
}) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(perms),
    'GET /api/v1/todo/items/counts': (_) => counts,
    'GET /api/v1/admin/worker': (_) => {
      'state': worker ?? 'ok',
      if (worker != 'never_seen') ...{
        'last_beat_at': '2027-01-26T08:00:00Z',
        'age_seconds': worker == 'down' ? 900 : 5,
        'late_after_seconds': 150,
        'interval_seconds': 30,
        'started_at': '2027-01-26T07:00:00Z',
        'version': '0.1.0',
        'host': 'worker-1',
      },
    },
  });
  final router = GoRouter(
    initialLocation: '/todo',
    routes: [
      ShellRoute(
        builder: (c, s, child) =>
            AppShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/todo', builder: (_, _) => const Text('TODO')),
          GoRoute(path: '/admin', builder: (_, _) => const Text('ADMIN')),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
        initialSessionProvider.overrideWithValue(_signedIn),
      ],
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
  return (http, router);
}

const _signedIn = Session(serverUrl: 'http://test', devUser: 'me@example.com');

final _badge = find.byKey(const ValueKey('notifications-badge'));
final _bell = find.byKey(const ValueKey('notifications-button'));

void main() {
  testWidgets('no badge at zero, and the list says so', (tester) async {
    await _shell(tester, ['todo.use']);
    expect(_bell, findsOneWidget);
    expect(_badge, findsNothing);
    await tester.tap(_bell);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notifications-empty')), findsOneWidget);
  });

  testWidgets('to-dos: overdue and open entries, badge counts entries', (
    tester,
  ) async {
    await _shell(
      tester,
      ['todo.use'],
      counts: {'open': 5, 'overdue': 2, 'due_today': 1},
    );
    expect(_badge, findsOneWidget);
    expect(
      find.descendant(of: _badge, matching: find.text('2')),
      findsOneWidget,
    );
    await tester.tap(_bell);
    await tester.pumpAndSettle();
    expect(find.text('2 overdue to-dos'), findsOneWidget);
    expect(find.text('3 open to-dos'), findsOneWidget);
    expect(find.text('1 due today'), findsOneWidget);
  });

  testWidgets(
    'a worker that is down is listed for administrators and opens Admin',
    (tester) async {
      final (_, router) = await _shell(tester, [
        'users.admin',
        'todo.use',
      ], worker: 'down');
      expect(
        find.descendant(of: _badge, matching: find.text('1')),
        findsOneWidget,
      );
      await tester.tap(_bell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('The background worker is down'));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/admin');
    },
  );

  testWidgets('a healthy worker adds nothing, and non-admins never see it', (
    tester,
  ) async {
    await _shell(tester, ['todo.use']);
    expect(_badge, findsNothing);
  });
}
