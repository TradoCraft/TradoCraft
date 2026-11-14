import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/field/job_screen.dart';
import 'package:tradocraft_app/features/field/jobs_page.dart';
import 'package:tradocraft_app/features/field/offline/job_cache.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/field/offline/offline_queue.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _job({
  String status = 'in_progress',
  bool t1 = false,
  List<Object?> tasks = const [],
}) => {
  'job': {
    'id': 'j1',
    'number': 'J2026-00001',
    'kind': 'maintenance',
    'status': status,
    'priority': 'normal',
    'title': 'Service pump station',
    'instructions': '',
    'customer_id': 'c1',
    'customer_name': 'Alpha Installaties NV',
    'site_name': '',
    'street': 'Havenlaan 10',
    'postal_code': '2000',
    'city': 'Antwerpen',
    'country_code': 'BE',
    'address': 'Havenlaan 10, 2000 Antwerpen',
    'completion_notes': '',
    'technicians': <Object?>[],
    'tasks_total': 2,
    'tasks_done': t1 ? 1 : 0,
    'report_sent_to': '',
  },
  'contact_phones': <Object?>[],
  'tasks': [
    {'id': 't1', 'position': 1, 'description': 'Replace seals', 'done': t1},
    {'id': 't2', 'position': 2, 'description': 'Pressure test', 'done': false},
    ...tasks,
  ],
  'work_logs': <Object?>[],
  'photos': <Object?>[],
  'equipment': <Object?>[],
  'parts': <Object?>[],
  'work_minutes': 0,
  'travel_minutes': 0,
};

class _World {
  bool offline = false;
  int? refuse; // status code for writes, when set
  late final FakeHttp http;
  final store = MemoryKvStore();
  var ticked = false;

  _World() {
    Object? net() => throw DioException.connectionError(
      requestOptions: RequestOptions(),
      reason: 'no signal',
    );
    Object? Function(Object?) route(Object? Function() ok) => (_) {
      if (offline) return net();
      if (refuse != null) {
        throw DioException(
          requestOptions: RequestOptions(),
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: refuse,
            data: {
              'error': 'conflict',
              'message': 'The job was reassigned to another technician',
            },
          ),
        );
      }
      return ok();
    };
    http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['field.read', 'field.work']),
      'GET /api/v1/field/jobs/j1': route(() => _job(t1: ticked)),
      'GET /api/v1/field/my-jobs': route(() => [_job()['job']]),
      'POST /api/v1/field/jobs/j1/start': route(() => _job()),
      'POST /api/v1/field/jobs/j1/complete': route(
        () => _job(status: 'completed'),
      ),
      'POST /api/v1/field/jobs/j1/tasks/t1/done': route(() {
        ticked = true;
        return _job(t1: true);
      }),
    });
  }
}

Future<void> _pump(WidgetTester tester, _World w, Widget home) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(w.http)),
        userKvStoreProvider.overrideWithValue(w.store),
      ],
      child: MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a tick made without signal shows at once, waits, and syncs later',
    (tester) async {
      final w = _World();
      await _pump(tester, w, const JobScreen(id: 'j1'));
      expect(find.text('0 of 2 done'), findsOneWidget);
      expect(find.byKey(const ValueKey('pending-sync-banner')), findsNothing);

      w.offline = true;
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      // Shown at once, marked as waiting, and the technician is told why.
      expect(find.text('1 change waiting to sync'), findsOneWidget);
      expect(find.text('1 of 2 done'), findsWidgets);
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isTrue,
      );
      expect(find.byIcon(Icons.cloud_upload_outlined), findsWidgets);
      expect(find.textContaining('No connection'), findsOneWidget);

      // Back online: "Sync now" from the list sends it.
      w.offline = false;
      await tester.tap(find.byKey(const ValueKey('pending-sync-banner')));
      await tester.pumpAndSettle();
      expect(find.text('Task ticked'), findsOneWidget);
      expect(find.text('Replace seals'), findsWidgets);
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(w.http.bodies['POST /api/v1/field/jobs/j1/tasks/t1/done'], {
        'done': true,
      });
      expect(find.text('Everything is synced.'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-sync-banner')), findsNothing);
      expect(find.text('1 of 2 done'), findsWidgets);
    },
  );

  testWidgets('starting and completing offline are queued in order and shown', (
    tester,
  ) async {
    final w = _World();
    await _pump(tester, w, const JobScreen(id: 'j1'));
    w.offline = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Complete job'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'What was done (and anything left open)'),
      'Seals replaced',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Complete job').last);
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget, reason: 'optimistic');
    expect(find.text('Seals replaced'), findsOneWidget);
    expect(find.text('1 change waiting to sync'), findsOneWidget);
    final q = ProviderScope.containerOf(tester.element(find.byType(JobScreen)))
        .read(offlineQueueProvider);
    expect(q.ops.single.type, OpType.complete);
    expect(q.ops.single.payload, {'notes': 'Seals replaced'});
  });

  testWidgets('a change the server refuses stays visible with its message', (
    tester,
  ) async {
    final w = _World();
    await _pump(tester, w, const JobScreen(id: 'j1'));
    w.offline = true;
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    w.offline = false;
    w.refuse = 409;
    final q = ProviderScope.containerOf(tester.element(find.byType(JobScreen)))
        .read(offlineQueueProvider);
    await tester.runAsync(() => q.process(force: true));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 needs your attention'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pending-sync-banner')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('reassigned to another technician'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    // Discard asks first, then removes it.
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(q.count, 0);
    expect(find.text('Everything is synced.'), findsOneWidget);
  });

  testWidgets('an assigned job opens from the local copy when offline', (
    tester,
  ) async {
    final w = _World();
    await JobCache(w.store).saveDetail(JobDetail.fromJson(_job(t1: true)));
    w.offline = true;
    await _pump(tester, w, const JobScreen(id: 'j1'));
    expect(find.text('J2026-00001  Service pump station'), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-note')), findsOneWidget);
    expect(find.textContaining('Offline: data from'), findsOneWidget);
    expect(find.text('1 of 2 done'), findsWidgets);
    // It can still be worked on: the change is queued.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('1 change waiting to sync'), findsOneWidget);
  });

  testWidgets('without a copy and without signal the error is shown', (
    tester,
  ) async {
    final w = _World()..offline = true;
    await _pump(tester, w, const JobScreen(id: 'j1'));
    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
  });

  testWidgets('the jobs list is kept for offline use', (tester) async {
    final w = _World();
    await _pump(tester, w, const JobsPage());
    expect(find.textContaining('Service pump station'), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-note')), findsNothing);

    w.offline = true;
    await _pump(tester, w, const SizedBox());
    await _pump(tester, w, const JobsPage());
    expect(find.textContaining('Service pump station'), findsOneWidget);
    expect(find.textContaining('Offline: data from'), findsOneWidget);
  });
}
