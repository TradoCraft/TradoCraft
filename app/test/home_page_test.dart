import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/home/home_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

void main() {
  testWidgets('HomePage renders only permitted cards and skips unpermitted API calls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['todo.use', 'helpdesk.read']),
      'GET /api/v1/todo/items': (_) => [
        {
          'id': 't1',
          'title': 'Call supplier A',
          'done': false,
          'mine': true,
          'notes': '',
          'owner_id': 'u1',
          'owner_name': 'Test User',
          'created_by': 'u1',
          'position': 0,
          'created_at': '2026-11-23T10:00:00Z',
          'updated_at': '2026-11-23T10:00:00Z',
        },
      ],
      'GET /api/v1/tickets': (_) => {
        'items': [
          {
            'id': 'tk1',
            'number': 'TCK-42',
            'subject': 'PLC wiring question',
            'status': 'open',
          },
        ],
        'total': 1,
      },
    });

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: HomePage())),
        GoRoute(path: '/todo', builder: (_, _) => const Text('TODO PAGE')),
        GoRoute(
          path: '/helpdesk/:id',
          builder: (_, s) => Text('TICKET ${s.pathParameters['id']}'),
        ),
      ],
    );

    final c = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
      ],
    );
    addTearDown(c.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
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

    expect(find.text('Call supplier A'), findsOneWidget);
    expect(find.text('TCK-42 · PLC wiring question'), findsOneWidget);
    expect(http.requests, isNot(contains('GET /api/v1/quotations')));
    expect(http.requests, isNot(contains('GET /api/v1/purchase-orders')));

    await tester.tap(find.text('TCK-42 · PLC wiring question'));
    await tester.pumpAndSettle();
    expect(find.text('TICKET tk1'), findsOneWidget);
  });

  testWidgets('AppShell home button navigates to /home', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['quotations.read']),
      'GET /api/v1/quotations': (_) => {'items': <Object?>[], 'total': 0},
    });

    final router = GoRouter(
      initialLocation: '/quotations',
      routes: [
        ShellRoute(
          builder: (_, s, child) =>
              AppShell(location: s.matchedLocation, child: child),
          routes: [
            GoRoute(
              path: '/quotations',
              builder: (_, _) => const Text('QUOTES'),
            ),
            GoRoute(path: '/home', builder: (_, _) => const HomePage()),
          ],
        ),
      ],
    );

    final c = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
      ],
    );
    addTearDown(c.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
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

    await tester.tap(find.byKey(const ValueKey('shell-home-button')));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
  });
}
