import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/worker_ui.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

const _uri = 'GET /api/v1/admin/worker';

Map<String, Object?> _status(String state) => {
  'state': state,
  if (state != 'never_seen') ...{
    'last_beat_at': '2027-01-26T08:00:00Z',
    'age_seconds': state == 'down' ? 900 : 5,
    'late_after_seconds': 150,
    'interval_seconds': 30,
    'started_at': '2027-01-26T07:00:00Z',
    'version': '0.1.0',
    'host': 'worker-1',
  },
};

Future<FakeHttp> _shell(
  WidgetTester tester,
  List<String> perms,
  Object? Function(Object?) worker, {
  bool wide = true,
}) async {
  tester.view.physicalSize = wide
      ? const Size(1400, 2000)
      : const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(perms),
    'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
    _uri: worker,
  });
  final router = GoRouter(
    initialLocation: '/quotations',
    routes: [
      ShellRoute(
        builder: (c, s, child) =>
            AppShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/quotations', builder: (_, _) => const Text('QUOTES')),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
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
  return http;
}

final _banner = find.byKey(const ValueKey('worker-banner'));

void main() {
  testWidgets('an administrator is warned while the worker is down', (
    tester,
  ) async {
    await _shell(tester, [
      'users.admin',
      'quotations.read',
    ], (_) => _status('down'));
    expect(_banner, findsOneWidget);
    expect(
      find.textContaining('The background worker has not run since'),
      findsOneWidget,
    );
  });

  testWidgets('also on a phone', (tester) async {
    await _shell(
      tester,
      ['users.admin', 'quotations.read'],
      (_) => _status('down'),
      wide: false,
    );
    expect(_banner, findsOneWidget);
  });

  testWidgets('a worker that never ran is a warning too', (tester) async {
    await _shell(tester, [
      'users.admin',
      'quotations.read',
    ], (_) => _status('never_seen'));
    expect(
      find.textContaining('No background worker has run yet'),
      findsOneWidget,
    );
  });

  testWidgets('nothing is shown while the worker runs', (tester) async {
    await _shell(tester, [
      'users.admin',
      'quotations.read',
    ], (_) => _status('running'));
    expect(_banner, findsNothing);
  });

  testWidgets('a failed check shows nothing', (tester) async {
    await _shell(tester, [
      'users.admin',
      'quotations.read',
    ], (_) => const FakeStatus(500, {'error': 'internal', 'message': 'x'}));
    expect(_banner, findsNothing);
  });

  testWidgets('users without users.admin never ask', (tester) async {
    final http = await _shell(tester, [
      'quotations.read',
    ], (_) => _status('down'));
    expect(_banner, findsNothing);
    expect(http.requests, isNot(contains(_uri)));
  });

  testWidgets('it asks again every minute and clears when the worker is back', (
    tester,
  ) async {
    var state = 'down';
    final http = await _shell(tester, [
      'users.admin',
      'quotations.read',
    ], (_) => _status(state));
    expect(_banner, findsOneWidget);
    state = 'running';
    await tester.pump(workerPollInterval);
    await tester.pumpAndSettle();
    expect(_banner, findsNothing);
    expect(http.requests.where((r) => r == _uri).length, 2);
  });
}
