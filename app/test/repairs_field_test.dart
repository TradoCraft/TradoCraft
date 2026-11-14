import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/field/job_screen.dart';
import 'package:tradocraft_app/features/repairs/repair_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/photos.dart';

import 'fake_http.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http,
  Widget home, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _repairDetail(
  String status, {
  String? department,
  List<Object?> photos = const [],
}) => {
  'repair': repairJson(
    status: status,
    department: department,
    photos: photos.length,
  ),
  'events': [
    {
      'id': 'e1',
      'kind': 'created',
      'to_status': 'received',
      'note': '',
      'actor_name': 'Support Agent',
      'created_at': '2026-11-06T10:00:00Z',
    },
    if (department != null)
      {
        'id': 'e2',
        'kind': 'routed',
        'from_status': 'received',
        'to_status': 'routed',
        'to_department': department,
        'note': 'Looks like the controller',
        'actor_name': 'Support Agent',
        'created_at': '2026-11-06T11:00:00Z',
      },
  ],
  'photos': photos,
};

void main() {
  test('client ids are valid version 4 UUIDs and differ', () {
    final a = newClientId(), b = newClientId();
    expect(
      a,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(a, isNot(b));
  });

  testWidgets(
    'triage offers routing; routing posts the department, colleague and note',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/repairs/r1': (_) => _repairDetail('received'),
        'GET /api/v1/me': (_) =>
            meJson(['repairs.read', 'repairs.write', 'repairs.route']),
        'GET /api/v1/departments': (_) => [
          departmentJson(
            'd1',
            'Electronics',
            members: [
              {'user_id': 'u9', 'display_name': 'Els Electronics'},
            ],
          ),
          departmentJson('d2', 'Mechanical workshop'),
        ],
        'POST /api/v1/repairs/r1/route': (_) =>
            _repairDetail('routed', department: 'Electronics'),
      });
      await _pump(tester, http, const RepairScreen(id: 'r1'));
      expect(find.text('R2026-00001  Alpha Installaties NV'), findsOneWidget);
      expect(find.text('Does not start'), findsOneWidget);
      expect(find.text('Not routed yet'), findsWidgets);
      // Received: it can be routed or cancelled, but work cannot start yet.
      expect(find.text('Route to department'), findsOneWidget);
      expect(find.text('Start work'), findsNothing);

      await tester.tap(find.text('Route to department'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Electronics').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String?>, 'Assign to'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Els Electronics').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Note for the department'),
        'Looks like the controller',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Route to department').last,
      );
      await tester.pumpAndSettle();

      expect(http.bodies['POST /api/v1/repairs/r1/route'], {
        'department_id': 'd1',
        'assigned_user_id': 'u9',
        'note': 'Looks like the controller',
      });
      // Now it waits in the department: start work is offered, and the history says where it went.
      expect(find.text('Start work'), findsOneWidget);
      expect(find.textContaining('→ Electronics'), findsOneWidget);
    },
  );

  testWidgets(
    'workshop staff without routing rights only get the workshop actions',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/repairs/r1': (_) =>
            _repairDetail('in_progress', department: 'Electronics'),
        'GET /api/v1/me': (_) => meJson(['repairs.read', 'repairs.write']),
        'GET /api/v1/departments': (_) => <Object?>[],
        'POST /api/v1/repairs/r1/status': (b) =>
            _repairDetail('completed', department: 'Electronics'),
      });
      await _pump(tester, http, const RepairScreen(id: 'r1'));
      expect(
        find.text('Route to department'),
        findsNothing,
        reason: 'routing is for those who triage',
      );
      expect(find.text('Mark as completed'), findsOneWidget);
      expect(find.text('Waiting for parts'), findsOneWidget);
      await tester.tap(find.text('Mark as completed'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes'),
        'Board replaced, tested',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/repairs/r1/status'], {
        'status': 'completed',
        'note': 'Board replaced, tested',
      });
      expect(find.text('Mark as shipped back'), findsOneWidget);
    },
  );

  testWidgets(
    'photos are shown from the server and new ones are uploaded as image bytes',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/repairs/r1': (_) => _repairDetail(
          'received',
          photos: [
            {
              'id': 'p1',
              'caption': 'Front panel',
              'filename': 'a.jpg',
              'content_type': 'image/jpeg',
              'size_bytes': 10,
              'uploader_name': 'Jan Peeters',
              'created_at': '2026-11-06T10:00:00Z',
            },
          ],
        ),
        'GET /api/v1/me': (_) => meJson(['repairs.read', 'repairs.write']),
        'GET /api/v1/departments': (_) => <Object?>[],
        'GET /api/v1/repairs/r1/photos/p1': (_) => fakeJpeg,
      });
      await _pump(tester, http, const RepairScreen(id: 'r1'));
      expect(find.text('Photos (1)'), findsOneWidget);
      expect(find.text('Front panel'), findsOneWidget);
      expect(find.text('by Jan Peeters'), findsOneWidget);
      expect(http.requests, contains('GET /api/v1/repairs/r1/photos/p1'));

      // The gallery hands what was picked to the caller, which sends it as the request body.
      final uploads = <PickedPhoto>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PhotoGallery(
              photos: const [],
              dio: fakeDio(http),
              pathFor: (id) => '/x/$id',
              pick: (_) async => [PickedPhoto(fakeJpeg, 'IMG_1.jpg')],
              onAdd: (p) async => uploads.addAll(p),
            ),
          ),
        ),
      );
      expect(find.text('No photos yet.'), findsOneWidget);
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(uploads.single.filename, 'IMG_1.jpg');
      expect(find.text('Photos added'), findsOneWidget);
    },
  );

  test(
    'uploading sends the raw image with a client id and file name',
    () async {
      final http = FakeHttp({
        'POST /api/v1/repairs/r1/photos': (_) => _repairDetail('received'),
      });
      await uploadPhoto(
        fakeDio(http),
        '/api/v1/repairs/r1/photos',
        PickedPhoto(fakeJpeg, 'IMG_1.jpg'),
        caption: 'Seal',
      );
      expect(http.bodies['POST /api/v1/repairs/r1/photos'], fakeJpeg);
    },
  );

  Map<String, Object?> job(String status, {bool task1 = false}) => {
    'job': {
      'id': 'j1',
      'number': 'J2026-00001',
      'kind': 'maintenance',
      'status': status,
      'priority': 'normal',
      'title': 'Service pump station',
      'instructions': 'Replace the seals.',
      'customer_id': 'c1',
      'customer_name': 'Alpha Installaties NV',
      'contact_name': 'Sofie Maes',
      'site_name': '',
      'street': 'Havenlaan 10',
      'postal_code': '2000',
      'city': 'Antwerpen',
      'country_code': 'BE',
      'address': 'Havenlaan 10, 2000 Antwerpen',
      'maps_url': 'https://www.google.com/maps/search/?api=1&query=x',
      'scheduled_start': '2026-11-09T07:00:00Z',
      'scheduled_end': '2026-11-09T11:00:00Z',
      'completion_notes': '',
      'technicians': [
        {'user_id': 'u1', 'display_name': 'Tom Technician'},
      ],
      'tasks_total': 2,
      'tasks_done': task1 ? 1 : 0,
      'report_sent_to': '',
    },
    'contact_phones': [
      {'label': 'mobile', 'number': '0475 00 00 22'},
    ],
    'tasks': [
      {
        'id': 't1',
        'position': 1,
        'description': 'Replace seals',
        'done': task1,
        'done_by_name': task1 ? 'Tom Technician' : null,
      },
      {
        'id': 't2',
        'position': 2,
        'description': 'Pressure test',
        'done': false,
      },
    ],
    'work_logs': <Object?>[],
    'photos': <Object?>[],
    'equipment': <Object?>[],
    'parts': <Object?>[],
    'work_minutes': 0,
    'travel_minutes': 0,
  };

  testWidgets(
    'a technician starts the job, ticks tasks and completes it with a report',
    (tester) async {
      var status = 'planned';
      var ticked = false;
      final http = FakeHttp({
        'GET /api/v1/field/jobs/j1': (_) => job(status, task1: ticked),
        'GET /api/v1/me': (_) => meJson(['field.read', 'field.work']),
        'POST /api/v1/field/jobs/j1/start': (_) {
          status = 'in_progress';
          return job(status);
        },
        'POST /api/v1/field/jobs/j1/tasks/t1/done': (_) {
          ticked = true;
          return job(status, task1: true);
        },
        'POST /api/v1/field/jobs/j1/complete': (_) {
          status = 'completed';
          return job(status, task1: true);
        },
      });
      await _pump(tester, http, const JobScreen(id: 'j1'));
      expect(find.text('J2026-00001  Service pump station'), findsOneWidget);
      expect(find.text('Havenlaan 10, 2000 Antwerpen'), findsOneWidget);
      expect(find.text('Navigate'), findsOneWidget);
      expect(
        find.textContaining('0475 00 00 22'),
        findsOneWidget,
        reason: 'a number to call on arrival',
      );
      expect(find.text('Replace the seals.'), findsOneWidget);
      expect(find.text('0 of 2 done'), findsOneWidget);
      // Technicians cannot plan: no edit or cancel.
      expect(find.text('Edit job'), findsNothing);
      expect(find.text('Cancel job'), findsNothing);

      await tester.tap(find.text('Start job'));
      await tester.pumpAndSettle();
      expect(find.text('Start job'), findsNothing);
      expect(find.text('Log work'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/field/jobs/j1/tasks/t1/done'], {
        'done': true,
      });
      expect(find.text('1 of 2 done'), findsWidgets);

      // The report is required; unticked tasks are pointed out.
      await tester.tap(find.widgetWithText(FilledButton, 'Complete job'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 done'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'What was done (and anything left open)',
        ),
        'Seals replaced; test next week.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Complete job').last);
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/field/jobs/j1/complete'], {
        'notes': 'Seals replaced; test next week.',
      });
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Complete job'), findsNothing);
    },
  );

  testWidgets(
    'a planner can edit, cancel and reopen; the job screen is translated',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/field/jobs/j1': (_) => job('planned'),
        'GET /api/v1/me': (_) => meJson(['field.read', 'field.plan']),
      });
      await _pump(tester, http, const JobScreen(id: 'j1'), locale: 'nl');
      expect(find.text('Opdracht bewerken'), findsOneWidget);
      expect(find.text('Opdracht annuleren'), findsOneWidget);
      expect(find.text('Waar naartoe'), findsOneWidget);
      expect(find.text('Navigeer'), findsOneWidget);
      expect(find.text('Gepland'), findsOneWidget);
    },
  );

  Future<void> pumpShell(
    WidgetTester tester,
    List<String> perms,
    String start, {
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(1200, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final http = FakeHttp({'GET /api/v1/me': (_) => meJson(perms)});
    Widget page(String name) => Center(child: Text('page $name'));
    final router = GoRouter(
      initialLocation: start,
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(location: state.matchedLocation, child: child),
          routes: [
            for (final p in [
              '/quotations',
              '/helpdesk',
              '/repairs',
              '/jobs',
              '/customers',
            ])
              GoRoute(path: p, builder: (_, _) => page(p)),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(fakeDio(http)),
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the navigation rail scrolls on a short window instead of overflowing',
    (tester) async {
      await pumpShell(
        tester,
        [
          'customers.read',
          'field.read',
          'helpdesk.read',
          'inventory.read',
          'kb.read',
          'opportunities.read',
          'orders.read',
          'packages.read',
          'planning.read',
          'products.read',
          'quotations.read',
          'repairs.intake',
          'repairs.read',
          'shipping.manage',
          'users.admin',
        ],
        '/repairs',
        height: 600,
      );
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .destinations
            .length,
        15,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);

      // A lower destination is reachable by scrolling the rail, and opens its page.
      final rail = find.byType(NavigationRail);
      await tester.drag(rail, const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: rail, matching: find.text('Customers')),
      );
      await tester.pumpAndSettle();
      expect(find.text('page /customers'), findsOneWidget);

      // The account menu sits below the destinations: scroll to it and open it.
      await tester.drag(rail, const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Support Agent'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a technician sees one section, and the default start page leads there',
    (tester) async {
      // The app opens on /quotations, which a technician has no rights for.
      await pumpShell(tester, ['field.read', 'field.work'], '/quotations');
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .destinations
            .length,
        1,
      );
      expect(
        find.text('page /jobs'),
        findsOneWidget,
        reason: 'redirected to their first section',
      );
      expect(find.text('Quotations'), findsNothing);
    },
  );

  testWidgets('support sees the sections it has rights for, and no jobs', (
    tester,
  ) async {
    await pumpShell(tester, [
      'helpdesk.read',
      'repairs.read',
      'customers.read',
    ], '/repairs');
    expect(
      tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .destinations
          .length,
      3,
    );
    expect(find.text('Repairs'), findsOneWidget);
    expect(find.text('Jobs'), findsNothing);
    expect(
      find.text('page /repairs'),
      findsOneWidget,
      reason: 'stays where it is',
    );
  });

  testWidgets('an account without any right is told so', (tester) async {
    await pumpShell(tester, [], '/repairs');
    expect(find.textContaining('no access to any section'), findsOneWidget);
  });
}
