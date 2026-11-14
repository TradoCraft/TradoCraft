import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/field/contract_screen.dart';
import 'package:tradocraft_app/features/field/job_screen.dart';
import 'package:tradocraft_app/features/field/signature_dialog.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
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

Map<String, Object?> _job(
  String status, {
  List<Object?> parts = const [],
  List<Object?> equipment = const [],
  Map<String, Object?>? signature,
  String? sentAt,
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
    'contact_name': 'Sofie Maes',
    'site_name': '',
    'street': 'Havenlaan 10',
    'postal_code': '2000',
    'city': 'Antwerpen',
    'country_code': 'BE',
    'address': 'Havenlaan 10, 2000 Antwerpen',
    'completion_notes': status == 'completed' ? 'All done' : '',
    'technicians': <Object?>[],
    'tasks_total': 0,
    'tasks_done': 0,
    'contract_id': 'k1',
    'contract_number': 'SC2027-00001',
    'due_date': '2027-03-31',
    'report_sent_at': sentAt,
    'report_sent_to': sentAt == null ? '' : 'sofie.maes@alpha.example',
  },
  'contact_phones': <Object?>[],
  'tasks': <Object?>[],
  'work_logs': <Object?>[],
  'photos': <Object?>[],
  'equipment': equipment,
  'parts': parts,
  'signature': signature,
  'work_minutes': 0,
  'travel_minutes': 0,
};

Map<String, Object?> _part() => {
  'id': 'p1',
  'description': 'Seal kit',
  'quantity': '2',
  'unit': 'pcs',
  'billable': true,
  'added_by_name': 'Tom Technician',
  'created_at': '2026-11-06T10:00:00Z',
};

Map<String, Object?> _unit(String serial, String status, String? until) => {
  'serial_unit_id': 'su-$serial',
  'product_code': 'PUMP-05',
  'product_name': 'Pump 0.5 kW',
  'serial_number': serial,
  'status': 'installed',
  'warranty_until': until,
  'warranty_note': '',
  'warranty_status': status,
};

void main() {
  testWidgets('parts are listed and added with a client id', (tester) async {
    var parts = <Object?>[];
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['field.read', 'field.work']),
      'GET /api/v1/field/jobs/j1': (_) => _job('in_progress', parts: parts),
      'POST /api/v1/field/jobs/j1/parts': (_) {
        parts = [_part()];
        return _job('in_progress', parts: parts);
      },
      'DELETE /api/v1/field/jobs/j1/parts/p1': (_) {
        parts = [];
        return _job('in_progress');
      },
    });
    await _pump(tester, http, const JobScreen(id: 'j1'));
    expect(find.text('Parts used'), findsOneWidget);
    expect(find.text('No parts recorded'), findsOneWidget);
    expect(find.text('Contract SC2027-00001 · Due 31/03/2027'), findsOneWidget);

    await tester.tap(find.text('Add part'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    // Product search, description, quantity, unit.
    await tester.enterText(fields.at(1), 'Seal kit');
    await tester.enterText(fields.at(2), '2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent =
        http.bodies['POST /api/v1/field/jobs/j1/parts'] as Map<String, Object?>;
    expect(sent['description'], 'Seal kit');
    expect(sent['quantity'], '2');
    expect(sent['billable'], true);
    expect(sent['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(find.textContaining('Seal kit'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    expect(find.text('No parts recorded'), findsOneWidget);
  });

  testWidgets('equipment shows the warranty status', (tester) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['field.read', 'field.work']),
      'GET /api/v1/field/jobs/j1': (_) => _job(
        'in_progress',
        equipment: [
          _unit('P-1', 'in_warranty', '2099-01-01T00:00:00Z'),
          _unit('P-2', 'expired', '2020-01-01T00:00:00Z'),
          _unit('P-3', 'unknown', null),
        ],
      ),
    });
    await _pump(tester, http, const JobScreen(id: 'j1'));
    expect(
      find.textContaining('In warranty · until 01/01/2099'),
      findsOneWidget,
    );
    expect(find.text('Warranty expired · until 01/01/2020'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('the signature is drawn, named and uploaded as a PNG', (
    tester,
  ) async {
    final http = FakeHttp({
      'POST /api/v1/field/jobs/j1/signature': (_) => _job(
        'completed',
        signature: {
          'signer_name': 'Sofie Maes',
          'declined': false,
          'decline_reason': '',
          'has_image': true,
          'signed_at': '2026-11-06T10:00:00Z',
        },
      ),
    });
    JobDetail? result;
    final detail = JobDetail.fromJson(_job('in_progress'));
    await _pump(
      tester,
      http,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showSignatureDialog(context, detail),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Nothing drawn yet: refused.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Draw a signature first'), findsOneWidget);
    expect(http.requests, isEmpty);

    await tester.drag(
      find.byKey(const ValueKey('signature-canvas')),
      const Offset(120, 40),
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();
    final sent = http.bodies['POST /api/v1/field/jobs/j1/signature'];
    expect(sent, isA<Uint8List>());
    expect((sent! as Uint8List).sublist(1, 4), [0x50, 0x4e, 0x47]);
    expect(http.queries.last['signer_name'], 'Sofie Maes');
    expect(http.queries.last['client_id'], isNotEmpty);
    expect(result?.signature?.signerName, 'Sofie Maes');
  });

  testWidgets('declining to sign needs a reason', (tester) async {
    final http = FakeHttp({
      'POST /api/v1/field/jobs/j1/signature/declined': (_) => _job(
        'completed',
        signature: {
          'signer_name': '',
          'declined': true,
          'decline_reason': 'No time',
          'has_image': false,
          'signed_at': '2026-11-06T10:00:00Z',
        },
      ),
    });
    JobDetail? result;
    final detail = JobDetail.fromJson(_job('completed'));
    await _pump(
      tester,
      http,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showSignatureDialog(context, detail),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(http.requests, isEmpty, reason: 'a reason is required');
    await tester.enterText(find.byType(TextField).last, 'No time');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent =
        http.bodies['POST /api/v1/field/jobs/j1/signature/declined']
            as Map<String, Object?>;
    expect(sent['reason'], 'No time');
    expect(result?.signature?.declined, true);
  });

  testWidgets('a completed job offers the report; sending queues the mail', (
    tester,
  ) async {
    var sent = false;
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['field.read', 'field.work']),
      'GET /api/v1/field/jobs/j1': (_) => _job('completed'),
      'POST /api/v1/field/jobs/j1/report/send': (_) {
        sent = true;
        return _job('completed', sentAt: '2026-11-06T12:00:00Z');
      },
    });
    await _pump(tester, http, const JobScreen(id: 'j1'));
    expect(find.text('Service report'), findsOneWidget);
    expect(find.text('View report (PDF)'), findsOneWidget);
    expect(find.text('Capture signature'), findsOneWidget);
    await tester.tap(find.text('Send report by e-mail'));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
    expect(find.text('The report will be sent'), findsOneWidget);
    expect(
      find.textContaining('Sent to sofie.maes@alpha.example on 06/11/2026'),
      findsOneWidget,
    );
    expect(
      find.text('Capture signature'),
      findsNothing,
      reason: 'the signature is locked once the report went out',
    );
  });

  Map<String, Object?> contract(String status) => {
    'id': 'k1',
    'number': 'SC2027-00001',
    'customer_id': 'c1',
    'customer_name': 'Alpha Installaties NV',
    'title': 'Pump maintenance',
    'status': status,
    'start_date': '2027-01-01',
    'end_date': '2027-12-31',
    'auto_renew': false,
    'response_hours': 4,
    'open_jobs': 0,
    'contact_id': null,
    'site_name': '',
    'street': '',
    'postal_code': '',
    'city': '',
    'country_code': 'BE',
    'notes': '',
    'equipment': [_unit('P-1', 'in_warranty', '2099-01-01')],
    'created_at': '2026-11-06T10:00:00Z',
    'visit_templates': [
      {
        'id': 'v1',
        'position': 1,
        'kind': 'maintenance',
        'title': 'Quarterly service',
        'instructions': 'Check seals',
        'tasks': ['Isolate', 'Inspect'],
        'recurrence': 'months',
        'interval_n': 3,
        'months': <Object?>[],
        'anchor_date': '2027-03-31',
        'lead_days': 14,
        'technicians': <Object?>[],
        'estimated_minutes': 90,
        'active': true,
      },
    ],
  };

  testWidgets('the contract editor shows visits and saves changes', (
    tester,
  ) async {
    var status = 'draft';
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['field.read', 'field.plan']),
      'GET /api/v1/field/contracts/k1': (_) => contract(status),
      'GET /api/v1/field/customers/c1/equipment': (_) => [
        {..._unit('P-1', 'in_warranty', '2099-01-01'), 'jobs': <Object?>[]},
      ],
      'GET /api/v1/field/contracts/k1/upcoming': (_) => [
        {
          'template_id': 'v1',
          'title': 'Quarterly service',
          'kind': 'maintenance',
          'due_date': '2027-03-31',
          'generate_on': '2027-03-17',
        },
      ],
      'GET /api/v1/field/contracts/k1/jobs': (_) => <Object?>[],
      'PUT /api/v1/field/contracts/k1': (_) => contract(status),
      'POST /api/v1/field/contracts/k1/activate': (_) {
        status = 'active';
        return contract(status);
      },
    });
    await _pump(tester, http, const ContractScreen(id: 'k1'));
    expect(find.text('SC2027-00001 · Pump maintenance'), findsOneWidget);
    expect(find.text('Alpha Installaties NV'), findsOneWidget);
    expect(find.text('Quarterly service'), findsWidgets);
    expect(find.text('31/03/2027 · Quarterly service'), findsOneWidget);
    expect(find.text('job created on 17/03/2027'), findsOneWidget);
    expect(find.text('Isolate\nInspect'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Pump maintenance'),
      'Pumps',
    );
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
    final body =
        http.bodies['PUT /api/v1/field/contracts/k1'] as Map<String, Object?>;
    expect(body['title'], 'Pumps');
    expect(body['equipment_ids'], ['su-P-1']);
    final tpl = (body['visit_templates']! as List).single as Map;
    expect(tpl['id'], 'v1');
    expect(tpl['recurrence'], 'months');
    expect(tpl['interval_n'], 3);
    expect(tpl['tasks'], ['Isolate', 'Inspect']);
    expect(tpl['anchor_date'], startsWith('2027-03-31'));

    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/field/contracts/k1/activate'));
    expect(find.text('Suspend'), findsOneWidget);
  });
}
