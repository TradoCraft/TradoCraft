import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/admin_page.dart';
import 'package:tradocraft_app/features/admin/imports/import_wizard.dart';
import 'package:tradocraft_app/features/admin/imports/mapping_logic.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/csv_transfer.dart';

import 'fake_http.dart';

const _entityJson = {
  'audit_entity': 'customer',
  'file_stem': 'customers',
  'key': 'customers',
  'key_column': 'code',
  'columns': [
    {'kind': 'code', 'name': 'code', 'required': true},
    {'kind': 'text', 'name': 'name', 'required': true},
    {'kind': 'text', 'name': 'city', 'required': false},
  ],
};

Map<String, Object?> fileJson({
  String format = 'xlsx',
  List<String> sheets = const ['Sheet1', 'Data'],
}) => {
  'id': 'f1',
  'filename': 'klanten.xlsx',
  'format': format,
  'sheets': sheets,
  'size_bytes': 2048,
};

Map<String, Object?> previewJson({
  List<String> columns = const ['code', 'name', 'city'],
  String? sheet = 'Sheet1',
}) => {
  'columns': columns,
  'format': 'xlsx',
  'header_row': 1,
  'row_count': 3,
  'rows': [
    for (final r in [
      ['C1', 'Acme', 'Gent'],
      ['C2', 'Beta', 'Luik'],
    ])
      r.take(columns.length).toList(),
  ],
  'sheet': sheet,
  'sheets': ['Sheet1', 'Data'],
};

Map<String, Object?> mappingJson(
  String id,
  String name,
  Map<String, String> pairs,
) => {
  'id': id,
  'name': name,
  'entity': 'customers',
  'columns': [
    for (final e in pairs.entries) {'column': e.key, 'field': e.value},
  ],
  'created_at': '2026-11-01T10:00:00Z',
  'updated_at': '2026-11-01T10:00:00Z',
};

Map<String, Object?> jobJson({
  String id = 'j1',
  String status = 'done',
  bool dryRun = true,
  int created = 0,
  int updated = 0,
  int unchanged = 0,
  int errorCount = 0,
  List<Map<String, Object?>> errors = const [],
  int processed = 0,
  int total = 0,
  String? phase,
  String? message,
  String? by = 'Ann Admin',
  String filename = 'klanten.xlsx',
}) => {
  'id': id,
  'status': status,
  'dry_run': dryRun,
  'entity': 'customers',
  'filename': filename,
  'format': 'xlsx',
  'sheet': 'Sheet1',
  'created': created,
  'updated': updated,
  'unchanged': unchanged,
  'error_count': errorCount,
  'errors': errors,
  'processed_rows': processed,
  'total_rows': total,
  'phase': phase,
  'message': message,
  'requested_by_name': by,
  'created_at': '2026-11-10T09:30:00Z',
};

final _xlsx = (
  name: 'klanten.xlsx',
  bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0xE9, 0xFF]),
);

class ImportsServer {
  ImportsServer({
    List<String> perms = const ['imports.admin'],
    this.entities = const [_entityJson],
    this.saved = const [],
    this.preview,
    this.dryRun,
    this.jobGet,
    this.history,
  }) {
    http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/imports/entities': (_) => entities,
      'POST /api/v1/imports/files': (_) => fileJson(),
      'GET /api/v1/imports/files/f1/preview': (_) => (preview ?? previewJson)(),
      'GET /api/v1/imports/mappings': (_) => saved,
      'PUT /api/v1/imports/mappings': (b) {
        final m = b as Map;
        return mappingJson('m9', m['name'] as String, {
          for (final c in m['columns'] as List) c['column']: c['field'],
        });
      },
      'DELETE /api/v1/imports/mappings/m1': (_) => null,
      'POST /api/v1/imports/jobs': (b) {
        final dry = (b as Map)['dry_run'] == true;
        return dry
            ? (dryRun ?? () => jobJson(created: 2, updated: 1, unchanged: 3))()
            : jobJson(dryRun: false, created: 2, updated: 1, unchanged: 3);
      },
      'GET /api/v1/imports/jobs/j1': (_) => (jobGet ?? () => jobJson())(),
      'GET /api/v1/imports/jobs/j1/errors': (_) =>
          'row,column,message\n3,code,Bad\n',
      'POST /api/v1/imports/jobs/j1/cancel': (_) =>
          jobJson(status: 'cancelled'),
      'GET /api/v1/imports/jobs': (_) =>
          (history ?? () => {'items': <Object?>[], 'total': 0})(),
    });
  }

  late final FakeHttp http;
  final List<Object?> entities;
  final List<Object?> saved;
  final Map<String, Object?> Function()? preview;
  final Object? Function()? dryRun;
  final Object? Function()? jobGet;
  final Object? Function()? history;

  int count(String key) => http.requests.where((r) => r == key).length;
  Map<String, dynamic> get jobBody => Map<String, dynamic>.from(
    http.bodies['POST /api/v1/imports/jobs'] as Map,
  );
}

Future<void> pump(
  WidgetTester tester,
  ImportsServer server, {
  PickedFile? picked,
  CsvSaver? saver,
  Size size = const Size(1000, 3600),
  Widget? home,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(server.http)),
        importFilePickerProvider.overrideWithValue(() async => picked),
        if (saver != null) csvSaverProvider.overrideWithValue(saver),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home ?? const AdminPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets requests finish without waiting for animations that never end (progress bars).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> upload(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('imp-choose-file')));
  await tester.pumpAndSettle();
}

Future<void> chooseEntity(
  WidgetTester tester, [
  String label = 'Customers',
]) async {
  await tester.tap(
    find.widgetWithText(DropdownButtonFormField<String>, 'What do you import?'),
  );
  await tester.pumpAndSettle();
  await tapText(tester, label);
}

/// Sets the field of file column [i] (currently showing [current]).
Future<void> setField(
  WidgetTester tester,
  int i,
  String? current,
  String item,
) async {
  await tester.tap(find.byKey(ValueKey('imp-field-$i-$current')));
  await tester.pumpAndSettle();
  await tapText(tester, item);
}

/// File, entity chosen: the columns step shows.
Future<void> toColumns(WidgetTester tester) async {
  await upload(tester);
  await chooseEntity(tester);
}

Finder checkButton() => find.byKey(const ValueKey('imp-run-check'));
Finder applyButton() => find.byKey(const ValueKey('imp-apply'));
bool enabled(WidgetTester tester, Finder f) =>
    tester.widget<FilledButton>(f).onPressed != null;

void main() {
  group('tab visibility', () {
    testWidgets('a user with only imports.admin gets the import page', (
      tester,
    ) async {
      await pump(tester, ImportsServer());
      expect(find.byKey(const ValueKey('imp-choose-file')), findsOneWidget);
      expect(find.text('1. File'), findsOneWidget);
    });

    testWidgets('the Import tab is offered next to the others', (tester) async {
      await pump(
        tester,
        ImportsServer(perms: ['users.admin', 'imports.admin', 'audit.view']),
      );
      expect(
        find.widgetWithText(ButtonSegment<String>, 'Import'),
        findsNothing,
      );
      expect(find.text('Import'), findsOneWidget);
      await tapText(tester, 'Import');
      expect(find.byKey(const ValueKey('imp-choose-file')), findsOneWidget);
    });

    testWidgets('without imports.admin there is no Import tab', (tester) async {
      await pump(tester, ImportsServer(perms: ['users.admin', 'audit.view']));
      expect(find.text('Import'), findsNothing);
      expect(find.byKey(const ValueKey('imp-choose-file')), findsNothing);
    });
  });

  group('file, entity, sheet and preview', () {
    testWidgets('upload sends the raw bytes, then entity and preview', (
      tester,
    ) async {
      final s = ImportsServer();
      await pump(tester, s, picked: _xlsx);
      // Later sections are only titles until the earlier ones are done.
      expect(find.text('What do you import?'), findsNothing);
      await upload(tester);
      expect(s.http.bodies['POST /api/v1/imports/files'], _xlsx.bytes);
      expect(
        s.http.queries[s.http.requests.indexOf('POST /api/v1/imports/files')],
        {'filename': 'klanten.xlsx'},
      );
      expect(find.text('klanten.xlsx'), findsOneWidget);
      expect(find.text('Format: Excel (XLSX), size: 2.0 KB'), findsOneWidget);
      // The first sheet is preselected and previewed.
      expect(
        s.http.queries[s.http.requests.indexOf(
          'GET /api/v1/imports/files/f1/preview',
        )],
        {'sheet': 'Sheet1'},
      );
      expect(
        find.text('3 data rows. The first 2 rows are shown.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('imp-preview')), findsOneWidget);
      expect(find.text('Acme'), findsOneWidget);
      await chooseEntity(tester);
      expect(find.text('3. Columns'), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-row-0')), findsOneWidget);
    });

    testWidgets('another sheet loads its own preview', (tester) async {
      final s = ImportsServer();
      await pump(tester, s, picked: _xlsx);
      await upload(tester);
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Sheet'),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Data');
      expect(s.http.queries.last, {
        'sheet': 'Data',
      }, reason: 'the preview of the chosen sheet');
      expect(s.count('GET /api/v1/imports/files/f1/preview'), 2);
    });

    testWidgets('413 names the limit, 422 shows the server message', (
      tester,
    ) async {
      final s = ImportsServer();
      s.http.routes['POST /api/v1/imports/files'] = (_) =>
          const FakeStatus(413, {'error': 'too_large', 'message': 'big'});
      await pump(tester, s, picked: _xlsx);
      await upload(tester);
      expect(
        find.text('The file is larger than the limit of 50 MiB.'),
        findsOneWidget,
      );
      s.http.routes['POST /api/v1/imports/files'] = (_) => const FakeStatus(
        422,
        {'error': 'invalid', 'message': 'Legacy .xls files are not supported'},
      );
      await upload(tester);
      expect(find.text('Legacy .xls files are not supported'), findsOneWidget);
      expect(
        find.text('The file is larger than the limit of 50 MiB.'),
        findsNothing,
      );
    });

    testWidgets('an empty file is refused locally', (tester) async {
      final s = ImportsServer();
      await pump(tester, s, picked: (name: 'a.csv', bytes: Uint8List(0)));
      await upload(tester);
      expect(find.text('The file is empty.'), findsOneWidget);
      expect(s.count('POST /api/v1/imports/files'), 0);
    });

    testWidgets('without a writable entity the page says what is needed', (
      tester,
    ) async {
      await pump(tester, ImportsServer(entities: const []), picked: _xlsx);
      await upload(tester);
      expect(
        find.textContaining('permission to write an entity'),
        findsOneWidget,
      );
      expect(find.text('3. Columns'), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-row-0')), findsNothing);
    });

    testWidgets('a CSV has no sheet picker', (tester) async {
      final s = ImportsServer();
      s.http.routes['POST /api/v1/imports/files'] = (_) =>
          fileJson(format: 'csv', sheets: const []);
      await pump(
        tester,
        s,
        picked: (name: 'a.csv', bytes: Uint8List(3)..[0] = 1),
      );
      await upload(tester);
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Sheet'),
        findsNothing,
      );
      expect(
        s.http.queries[s.http.requests.indexOf(
          'GET /api/v1/imports/files/f1/preview',
        )],
        isEmpty,
      );
    });
  });

  group('the column mapping', () {
    testWidgets('a saved mapping that covers the header is proposed', (
      tester,
    ) async {
      final s = ImportsServer(
        saved: [
          mappingJson('m1', 'Dutch', {
            'code': 'code',
            'name': 'name',
            'city': 'city',
          }),
          mappingJson('m2', 'Other', {'Kode': 'code', 'Naam': 'name'}),
          mappingJson('m3', 'Elsewhere', {'Nope': 'code'}),
        ],
        preview: () => previewJson(columns: ['Kode', 'Naam', 'Plaats']),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      expect(
        find.text('Columns taken from the saved mapping Other.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('imp-field-0-code')), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-field-1-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-field-2-null')), findsOneWidget);
    });

    testWidgets('without a saved mapping equal names are paired', (
      tester,
    ) async {
      final s = ImportsServer(
        preview: () => previewJson(columns: [' Code ', 'NAME', 'Plaats']),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      expect(
        find.textContaining('paired with fields of the same name'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('imp-field-0-code')), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-field-1-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-field-2-null')), findsOneWidget);
      // Samples come from the preview.
      expect(find.text('Example: C1'), findsOneWidget);
    });

    testWidgets('the key column unmapped blocks the check', (tester) async {
      final s = ImportsServer(
        preview: () => previewJson(columns: ['Kode', 'name', 'city']),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      expect(
        find.text(
          'Choose a file column for the key field code: rows are matched on it.',
        ),
        findsOneWidget,
      );
      expect(find.text('4. Check'), findsOneWidget);
      expect(checkButton(), findsNothing);
      // Choosing it unblocks.
      await setField(tester, 0, null, 'code (Key) *');
      expect(
        find.textContaining('Choose a file column for the key'),
        findsNothing,
      );
      expect(enabled(tester, checkButton()), isTrue);
    });

    testWidgets('a field chosen twice blocks the check', (tester) async {
      await pump(tester, ImportsServer(), picked: _xlsx);
      await toColumns(tester);
      expect(enabled(tester, checkButton()), isTrue);
      await setField(tester, 1, 'name', 'code (Key) *');
      expect(
        find.text('The field code is chosen for more than one column.'),
        findsWidgets,
      );
      expect(checkButton(), findsNothing);
      await setField(tester, 1, 'code', 'Ignore');
      expect(checkButton(), findsOneWidget);
    });

    testWidgets('unmapped fields are listed', (tester) async {
      await pump(
        tester,
        ImportsServer(preview: () => previewJson(columns: ['code', 'x'])),
        picked: _xlsx,
      );
      await toColumns(tester);
      expect(find.text('Needed to create new records: name'), findsOneWidget);
      expect(find.text('Fields without a column: name, city'), findsOneWidget);
    });

    testWidgets('a mapping is saved, replaced after confirmation and deleted', (
      tester,
    ) async {
      final s = ImportsServer(
        saved: [
          mappingJson('m1', 'Dutch', {
            'code': 'code',
            'name': 'name',
            'city': 'city',
          }),
        ],
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(find.byKey(const ValueKey('imp-save-mapping')));
      await tester.pumpAndSettle();
      // A new name: saved at once.
      await tester.enterText(
        find.byKey(const ValueKey('imp-mapping-name')),
        'Mine',
      );
      await tester.tap(find.byKey(const ValueKey('imp-mapping-name-ok')));
      await tester.pumpAndSettle();
      expect(s.count('PUT /api/v1/imports/mappings'), 1);
      expect(s.http.bodies['PUT /api/v1/imports/mappings'], {
        'name': 'Mine',
        'entity': 'customers',
        'columns': [
          {'column': 'code', 'field': 'code'},
          {'column': 'name', 'field': 'name'},
          {'column': 'city', 'field': 'city'},
        ],
      });
      expect(find.text('Mapping Mine saved'), findsOneWidget);
      // The same name as a saved one: asks first.
      await tester.tap(find.byKey(const ValueKey('imp-save-mapping')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('imp-mapping-name')),
        'Dutch',
      );
      await tester.tap(find.byKey(const ValueKey('imp-mapping-name-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Replace the mapping?'), findsOneWidget);
      expect(s.count('PUT /api/v1/imports/mappings'), 1);
      await tester.tap(find.byKey(const ValueKey('imp-overwrite-confirm')));
      await tester.pumpAndSettle();
      expect(s.count('PUT /api/v1/imports/mappings'), 2);
      // Cancelling the question saves nothing.
      await tester.tap(find.byKey(const ValueKey('imp-save-mapping')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('imp-mapping-name')),
        'Dutch',
      );
      await tester.tap(find.byKey(const ValueKey('imp-mapping-name-ok')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');
      expect(s.count('PUT /api/v1/imports/mappings'), 2);
      // Delete from the list of saved mappings.
      await tester.tap(find.byKey(const ValueKey('imp-saved-mappings')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete mapping Dutch'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete mapping Dutch'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('imp-delete-mapping-confirm')),
      );
      await tester.pumpAndSettle();
      expect(s.count('DELETE /api/v1/imports/mappings/m1'), 1);
      // Snack bars queue: the earlier ones have to go first.
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.text('Mapping Dutch deleted'), findsOneWidget);
    });

    testWidgets('another saved mapping can be taken from the list', (
      tester,
    ) async {
      final s = ImportsServer(
        saved: [
          mappingJson('m5', 'Cities', {'code': 'code', 'city': 'name'}),
        ],
        preview: () => previewJson(columns: ['code', 'city', 'name']),
      );
      s.http.routes['GET /api/v1/imports/mappings'] = (_) => [
        mappingJson('m5', 'Cities', {'code': 'code', 'city': 'name'}),
      ];
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      // 'Cities' covers code and city, so it was proposed: city -> name, name ignored.
      expect(find.byKey(const ValueKey('imp-field-1-name')), findsOneWidget);
      await setField(tester, 1, 'name', 'city');
      expect(find.byKey(const ValueKey('imp-field-1-city')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('imp-saved-mappings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('imp-mapping-Cities')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('imp-field-1-name')), findsOneWidget);
    });
  });

  group('check and import', () {
    testWidgets('identity mapping sends no columns', (tester) async {
      final s = ImportsServer();
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      expect(s.jobBody, {
        'file_id': 'f1',
        'entity': 'customers',
        'sheet': 'Sheet1',
        'dry_run': true,
      });
      expect(s.jobBody.containsKey('columns'), isFalse);
    });

    testWidgets('renamed or ignored columns are sent as pairs', (tester) async {
      final s = ImportsServer(
        preview: () => previewJson(columns: ['Kode', 'name', 'extra']),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await setField(tester, 0, null, 'code (Key) *');
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      expect(s.jobBody['columns'], [
        {'column': 'Kode', 'field': 'code'},
        {'column': 'name', 'field': 'name'},
      ]);
    });

    testWidgets('a dry run with errors lists them and keeps Apply disabled', (
      tester,
    ) async {
      final s = ImportsServer(
        dryRun: () => jobJson(
          errorCount: 2,
          errors: [
            {'row': 3, 'column': 'name', 'message': 'Name is required'},
            {'row': 5, 'message': 'Duplicate code'},
          ],
        ),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      expect(find.text('Done with 2 errors'), findsOneWidget);
      expect(
        find.text('2 problems found. Nothing has been imported.'),
        findsOneWidget,
      );
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Row 3, column name'), findsOneWidget);
      expect(find.text('Row 5'), findsOneWidget);
      expect(enabled(tester, applyButton()), isFalse);
    });

    testWidgets('the error report is downloaded through the saver', (
      tester,
    ) async {
      String? name;
      String? text;
      final s = ImportsServer(
        dryRun: () => jobJson(
          errorCount: 250,
          errors: [
            for (var i = 1; i <= 100; i++) {'row': i, 'message': 'Bad $i'},
          ],
        ),
      );
      await pump(
        tester,
        s,
        picked: _xlsx,
        saver: (n, b) async {
          name = n;
          text = utf8.decode(b);
          return true;
        },
      );
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Showing the first 100 of 250 problems. The error report lists the same problems. A file with very many problems lists only the first ones: fix these and check again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('imp-download-errors')));
      await tester.pumpAndSettle();
      expect(s.count('GET /api/v1/imports/jobs/j1/errors'), 1);
      expect(name, 'import-errors-j1.csv');
      expect(text, contains('3,code,Bad'));
      expect(find.text('Saved import-errors-j1.csv'), findsOneWidget);
    });

    testWidgets('a clean check shows the counts and enables Apply', (
      tester,
    ) async {
      await pump(
        tester,
        ImportsServer(
          dryRun: () => jobJson(created: 40, updated: 50, unchanged: 60),
        ),
        picked: _xlsx,
      );
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      expect(
        find.text('No problems found. Nothing has been imported yet.'),
        findsOneWidget,
      );
      expect(find.text('To create'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(enabled(tester, applyButton()), isTrue);
    });

    testWidgets('changing the mapping after a check disables Apply again', (
      tester,
    ) async {
      await pump(tester, ImportsServer(), picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      expect(enabled(tester, applyButton()), isTrue);
      await setField(tester, 2, 'city', 'Ignore');
      expect(enabled(tester, applyButton()), isFalse);
      expect(find.textContaining('changed after this check'), findsOneWidget);
      // Back to what was checked: the check holds again.
      await setField(tester, 2, null, 'city');
      expect(enabled(tester, applyButton()), isTrue);
      expect(find.textContaining('changed after this check'), findsNothing);
    });

    testWidgets('another sheet or entity invalidates the check too', (
      tester,
    ) async {
      await pump(tester, ImportsServer(), picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Sheet'),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Data');
      expect(find.byKey(const ValueKey('imp-apply')), findsNothing);
    });

    testWidgets('apply asks first, imports and shows the result', (
      tester,
    ) async {
      final s = ImportsServer();
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      await tester.tap(applyButton());
      await tester.pumpAndSettle();
      expect(find.text('Import Customers?'), findsOneWidget);
      expect(
        find.text('2 will be created and 1 updated. This changes data.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('imp-apply-confirm')));
      await tester.pumpAndSettle();
      expect(s.jobBody['dry_run'], false);
      expect(find.text('Import complete'), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-another')), findsOneWidget);
      // Import another file starts over.
      await tester.tap(find.byKey(const ValueKey('imp-another')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('imp-preview')), findsNothing);
      expect(find.byKey(const ValueKey('imp-choose-file')), findsOneWidget);
    });

    testWidgets('declining the question writes nothing', (tester) async {
      final s = ImportsServer();
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      await tester.tap(applyButton());
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');
      expect(
        s.http.bodies['POST /api/v1/imports/jobs'],
        containsPair('dry_run', true),
      );
      expect(enabled(tester, applyButton()), isTrue);
    });

    testWidgets('a failed request shows the server message', (tester) async {
      final s = ImportsServer(
        dryRun: () => const FakeStatus(422, {
          'error': 'invalid',
          'message': 'Unknown sheet "x". Sheets: A, B',
        }),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      expect(find.textContaining('Unknown sheet'), findsOneWidget);
      expect(enabled(tester, checkButton()), isTrue);
    });

    testWidgets('a failed job shows its message', (tester) async {
      final s = ImportsServer(
        dryRun: () =>
            jobJson(status: 'failed', message: 'The file could not be read'),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await tester.pumpAndSettle();
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('The file could not be read'), findsOneWidget);
      expect(enabled(tester, applyButton()), isFalse);
    });

    testWidgets('a background job is polled until it is done', (tester) async {
      var polls = 0;
      final s = ImportsServer(
        dryRun: () => const FakeStatus(202, {
          'id': 'j1',
          'status': 'queued',
          'dry_run': true,
          'entity': 'customers',
          'filename': 'big.xlsx',
          'format': 'xlsx',
          'created': 0,
          'updated': 0,
          'unchanged': 0,
          'error_count': 0,
          'errors': <Object?>[],
          'processed_rows': 0,
          'total_rows': 0,
          'created_at': '2026-11-10T09:30:00Z',
        }),
        jobGet: () {
          polls++;
          return switch (polls) {
            1 => jobJson(
              status: 'running',
              phase: 'validating',
              processed: 50,
              total: 100,
            ),
            2 => jobJson(
              status: 'running',
              phase: 'writing',
              processed: 90,
              total: 100,
            ),
            _ => jobJson(created: 7),
          };
        },
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await settle(tester);
      expect(find.text('Queued'), findsWidgets);
      expect(find.byKey(const ValueKey('imp-cancel-job')), findsOneWidget);
      expect(find.textContaining('leave this page'), findsOneWidget);
      expect(s.count('GET /api/v1/imports/jobs/j1'), 0);
      // Nothing is asked before the interval has passed.
      await tester.pump(const Duration(seconds: 1));
      expect(s.count('GET /api/v1/imports/jobs/j1'), 0);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(s.count('GET /api/v1/imports/jobs/j1'), 1);
      expect(find.text('Validating the rows, 50 of 100 rows'), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-cancel-job')), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator).first,
      );
      expect(bar.value, 0.5);
      expect(enabled(tester, checkButton()), isFalse);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('Writing the records, 90 of 100 rows'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(s.count('GET /api/v1/imports/jobs/j1'), 3);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(enabled(tester, applyButton()), isTrue);
      // Polling stopped.
      await tester.pump(const Duration(seconds: 10));
      expect(s.count('GET /api/v1/imports/jobs/j1'), 3);
    });

    testWidgets('leaving the page stops the polling', (tester) async {
      final s = ImportsServer(
        dryRun: () => const FakeStatus(202, {
          'id': 'j1',
          'status': 'queued',
          'dry_run': true,
          'entity': 'customers',
          'filename': 'big.xlsx',
          'format': 'xlsx',
          'created': 0,
          'updated': 0,
          'unchanged': 0,
          'error_count': 0,
          'errors': <Object?>[],
          'processed_rows': 0,
          'total_rows': 0,
          'created_at': '2026-11-10T09:30:00Z',
        }),
        jobGet: () => jobJson(status: 'running', phase: 'reading', total: 10),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(s.count('GET /api/v1/imports/jobs/j1'), 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(s.count('GET /api/v1/imports/jobs/j1'), 1);
    });

    testWidgets('a queued job can be cancelled', (tester) async {
      final s = ImportsServer(
        dryRun: () => const FakeStatus(202, {
          'id': 'j1',
          'status': 'queued',
          'dry_run': true,
          'entity': 'customers',
          'filename': 'big.xlsx',
          'format': 'xlsx',
          'created': 0,
          'updated': 0,
          'unchanged': 0,
          'error_count': 0,
          'errors': <Object?>[],
          'processed_rows': 0,
          'total_rows': 0,
          'created_at': '2026-11-10T09:30:00Z',
        }),
      );
      await pump(tester, s, picked: _xlsx);
      await toColumns(tester);
      await tester.tap(checkButton());
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('imp-cancel-job')));
      await settle(tester);
      expect(s.count('POST /api/v1/imports/jobs/j1/cancel'), 1);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.byKey(const ValueKey('imp-cancel-job')), findsNothing);
      expect(enabled(tester, applyButton()), isFalse);
      // No more polling after the cancel.
      await tester.pump(const Duration(seconds: 10));
      expect(s.count('GET /api/v1/imports/jobs/j1'), 0);
      expect(enabled(tester, checkButton()), isTrue);
    });
  });

  group('history', () {
    Future<void> openHistory(WidgetTester tester) async {
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a loading state, then the empty state', (tester) async {
      final gate = Completer<void>();
      final s = ImportsServer();
      s.http.routes['GET /api/v1/imports/jobs'] = (_) async {
        await gate.future;
        return {'items': <Object?>[], 'total': 0};
      };
      await pump(tester, s);
      await tester.tap(find.text('History'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('No imports yet.'), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      var fail = true;
      final s = ImportsServer();
      s.http.routes['GET /api/v1/imports/jobs'] = (_) => fail
          ? const FakeStatus(500, {'error': 'x', 'message': 'Boom'})
          : {
              'items': [jobJson()],
              'total': 1,
            };
      await pump(tester, s);
      await openHistory(tester);
      expect(find.text('Boom'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const ValueKey('imp-history-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Boom'), findsNothing);
      expect(find.text('klanten.xlsx'), findsOneWidget);
    });

    testWidgets('each status looks different and says what it is', (
      tester,
    ) async {
      final s = ImportsServer(
        history: () => {
          'total': 6,
          'items': [
            jobJson(id: 'a', status: 'queued', filename: 'a.xlsx'),
            jobJson(
              id: 'b',
              status: 'running',
              filename: 'b.xlsx',
              phase: 'writing',
              processed: 5,
              total: 10,
              dryRun: false,
            ),
            jobJson(
              id: 'c',
              filename: 'c.xlsx',
              created: 4,
              updated: 5,
              unchanged: 6,
            ),
            jobJson(id: 'd', filename: 'd.xlsx', errorCount: 2),
            jobJson(
              id: 'e',
              status: 'failed',
              filename: 'e.xlsx',
              message: 'Lost',
            ),
            jobJson(
              id: 'f',
              status: 'cancelled',
              filename: 'f.xlsx',
              by: null,
              dryRun: false,
            ),
          ],
        },
      );
      await pump(tester, s);
      await openHistory(tester);
      expect(find.text('Queued'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Done with 2 errors'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(
        find.text('4 to create, 5 to update, 6 unchanged'),
        findsOneWidget,
      );
      expect(find.textContaining('Customers · Check only'), findsWidgets);
      expect(find.textContaining('By Ann Admin'), findsWidgets);
      expect(find.text('Writing the records, 5 of 10 rows'), findsOneWidget);
    });

    testWidgets('refreshes while a job is queued or running, then stops', (
      tester,
    ) async {
      var calls = 0;
      final s = ImportsServer(
        history: () {
          calls++;
          return {
            'total': 1,
            'items': [
              calls < 3
                  ? jobJson(status: 'running', phase: 'reading', total: 10)
                  : jobJson(),
            ],
          };
        },
      );
      await pump(tester, s);
      await openHistory(tester);
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(calls, 3);
      expect(find.text('Done'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      expect(calls, 3);
    });

    testWidgets('the detail shows the errors and downloads the report', (
      tester,
    ) async {
      String? name;
      final s = ImportsServer(
        history: () => {
          'total': 1,
          'items': [jobJson(errorCount: 1)],
        },
        jobGet: () => jobJson(
          errorCount: 1,
          errors: [
            {'row': 9, 'column': 'code', 'message': 'Code is empty'},
          ],
        ),
      );
      await pump(
        tester,
        s,
        saver: (n, b) async {
          name = n;
          return true;
        },
      );
      await openHistory(tester);
      await tester.tap(find.byKey(const ValueKey('imp-job-j1')));
      await tester.pumpAndSettle();
      expect(find.text('Import details'), findsOneWidget);
      expect(find.text('Code is empty'), findsOneWidget);
      expect(find.text('Row 9, column code'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('imp-download-errors')));
      await tester.pumpAndSettle();
      expect(name, 'import-errors-j1.csv');
    });

    testWidgets(
      'the detail of a failed job shows why, a queued one can be cancelled',
      (tester) async {
        var status = 'failed';
        final s = ImportsServer(
          history: () => {
            'total': 1,
            'items': [jobJson(status: status)],
          },
          jobGet: () => jobJson(
            status: status,
            message: status == 'failed' ? 'Worker fault' : null,
          ),
        );
        await pump(tester, s);
        await openHistory(tester);
        await tester.tap(find.byKey(const ValueKey('imp-job-j1')));
        await tester.pumpAndSettle();
        expect(find.text('Worker fault'), findsOneWidget);
        await tapText(tester, 'Close');
        status = 'queued';
        await tester.tap(find.byKey(const ValueKey('imp-history-refresh')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('imp-job-j1')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('imp-cancel-job')));
        await settle(tester);
        expect(s.count('POST /api/v1/imports/jobs/j1/cancel'), 1);
        // Close the dialog: its own refresh timer ends with it.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      },
    );

    testWidgets('long histories load successive pages, up to the last one', (
      tester,
    ) async {
      late ImportsServer s;
      s = ImportsServer(
        history: () {
          final offset = (s.http.queries.last['offset'] ?? 0) as int;
          return {
            'total': 500,
            'items': [jobJson(id: 'h$offset')],
          };
        },
      );
      await pump(tester, s, picked: null);
      await openHistory(tester);
      expect(s.http.queries.last['limit'], 50);
      expect(s.http.queries.last['offset'], 0);
      final more = find.byKey(const ValueKey('imp-history-more'));
      // Past 200 jobs the button stays: the pages go on by offset.
      for (final offset in [50, 100, 150, 200, 250]) {
        await tester.ensureVisible(more);
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(s.http.queries.last['offset'], offset);
        expect(s.http.queries.last['limit'], 50);
        expect(find.byKey(ValueKey('imp-job-h$offset')), findsOneWidget);
      }
      // The earlier pages are still listed.
      expect(find.byKey(const ValueKey('imp-job-h0')), findsOneWidget);
      expect(more, findsOneWidget);
    });
  });

  group('races in the wizard', () {
    ({ProviderContainer container, FakeHttp http}) setup(
      Map<String, Object? Function(Object?)> routes,
    ) {
      final http = FakeHttp({
        'POST /api/v1/imports/files': (_) => fileJson(),
        'GET /api/v1/imports/files/f1/preview': (_) => previewJson(),
        'GET /api/v1/imports/mappings': (_) => <Object?>[],
        ...routes,
      });
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      );
      addTearDown(container.dispose);
      container.listen(importWizardProvider, (_, _) {});
      return (container: container, http: http);
    }

    final entity = ImportDescription.fromJson(_entityJson);
    Map<String, Object?> queued(String id, {bool dry = false}) => {
      ...jobJson(id: id, status: 'queued', dryRun: dry),
    };

    Future<void> ready(WidgetTester tester, ProviderContainer c) async {
      final w = c.read(importWizardProvider.notifier);
      unawaited(w.selectEntity(entity));
      await settle(tester);
      unawaited(w.upload(_xlsx));
      await settle(tester);
    }

    testWidgets('a check started during an import does not stop its polling', (
      tester,
    ) async {
      var polls = 0;
      final t = setup({
        'POST /api/v1/imports/jobs': (b) =>
            (b as Map)['dry_run'] == true ? jobJson(id: 'd1') : queued('a1'),
        'GET /api/v1/imports/jobs/a1': (_) {
          polls++;
          return jobJson(id: 'a1', dryRun: false, created: 2);
        },
      });
      final w = t.container.read(importWizardProvider.notifier);
      await ready(tester, t.container);
      unawaited(w.run(dryRun: true));
      await settle(tester);
      unawaited(w.run(dryRun: false));
      await settle(tester);
      expect(t.container.read(importWizardProvider).apply.job?.id, 'a1');
      // A new check while the import is queued.
      unawaited(w.run(dryRun: true));
      await settle(tester);
      await tester.pump(importPollInterval);
      await settle(tester);
      expect(polls, 1);
      expect(t.container.read(importWizardProvider).apply.job?.status, 'done');
    });

    testWidgets(
      'a poll that was on its way when the run was cleared is dropped',
      (tester) async {
        final gate = Completer<Object?>();
        final t = setup({
          'POST /api/v1/imports/jobs': (_) => queued('j1', dry: true),
          'GET /api/v1/imports/jobs/j1': (_) => gate.future,
        });
        final w = t.container.read(importWizardProvider.notifier);
        await ready(tester, t.container);
        unawaited(w.run(dryRun: true));
        await settle(tester);
        await tester.pump(importPollInterval);
        await settle(tester);
        expect(t.http.requests.last, 'GET /api/v1/imports/jobs/j1');
        w.reset();
        gate.complete(jobJson(created: 5));
        await settle(tester);
        expect(t.container.read(importWizardProvider).dry.job, isNull);
      },
    );

    testWidgets('a job created after the settings changed is not shown', (
      tester,
    ) async {
      final gate = Completer<Object?>();
      final t = setup({'POST /api/v1/imports/jobs': (_) => gate.future});
      final w = t.container.read(importWizardProvider.notifier);
      await ready(tester, t.container);
      unawaited(w.run(dryRun: true));
      await settle(tester);
      unawaited(w.selectSheet('Data'));
      await settle(tester);
      gate.complete(jobJson());
      await settle(tester);
      final s = t.container.read(importWizardProvider);
      expect(s.dry.job, isNull);
      expect(s.dry.starting, isFalse);
    });

    testWidgets('a cancel answer is not overwritten by a late poll', (
      tester,
    ) async {
      final gate = Completer<Object?>();
      final t = setup({
        'POST /api/v1/imports/jobs': (_) => queued('j1', dry: true),
        'GET /api/v1/imports/jobs/j1': (_) => gate.future,
        'POST /api/v1/imports/jobs/j1/cancel': (_) =>
            jobJson(status: 'cancelled'),
      });
      final w = t.container.read(importWizardProvider.notifier);
      await ready(tester, t.container);
      unawaited(w.run(dryRun: true));
      await settle(tester);
      await tester.pump(importPollInterval);
      await settle(tester);
      unawaited(w.cancel(dryRun: true));
      await settle(tester);
      gate.complete(queued('j1', dry: true));
      await settle(tester);
      expect(
        t.container.read(importWizardProvider).dry.job?.status,
        'cancelled',
      );
    });

    testWidgets(
      'saved mappings arriving late do not overwrite edited columns',
      (tester) async {
        final gate = Completer<Object?>();
        final t = setup({'GET /api/v1/imports/mappings': (_) => gate.future});
        final w = t.container.read(importWizardProvider.notifier);
        unawaited(w.selectEntity(entity));
        await settle(tester);
        unawaited(w.upload(_xlsx));
        await settle(tester);
        expect(t.container.read(importWizardProvider).fields, [
          'code',
          'name',
          'city',
        ]);
        w.setField(2, null);
        gate.complete([
          mappingJson('m1', 'Other', {'code': 'code', 'city': 'name'}),
        ]);
        await settle(tester);
        final s = t.container.read(importWizardProvider);
        expect(s.saved, hasLength(1));
        expect(s.fields, ['code', 'name', null]);
      },
    );

    testWidgets('saved mappings arriving after the screen is gone do nothing', (
      tester,
    ) async {
      final gate = Completer<Object?>();
      final t = setup({'GET /api/v1/imports/mappings': (_) => gate.future});
      final w = t.container.read(importWizardProvider.notifier);
      unawaited(w.selectEntity(entity));
      await settle(tester);
      t.container.dispose();
      gate.complete(<Object?>[]);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no overflow at 360 px', (tester) async {
    final s = ImportsServer(
      saved: [
        mappingJson('m1', 'A mapping with a rather long name indeed', {
          'code': 'code',
        }),
      ],
      preview: () => previewJson(
        columns: [
          'A very long file column heading that goes on',
          'name',
          'city',
        ],
      ),
    );
    await pump(tester, s, picked: _xlsx, size: const Size(360, 640));
    await upload(tester);
    await chooseEntity(tester);
    final list = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('imp-save-mapping')),
      200,
      scrollable: list,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('imp-row-2')),
      200,
      scrollable: list,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('imp-saved-mappings')),
      -200,
      scrollable: list,
    );
    await tester.tap(find.byKey(const ValueKey('imp-saved-mappings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('mapping rules', () {
    final entity = ImportDescription.fromJson(_entityJson);
    ImportMapping mapping(String name, Map<String, String> pairs) =>
        ImportMapping.fromJson(mappingJson('id-$name', name, pairs));

    test('the saved mapping covering most columns wins', () {
      final small = mapping('small', {'code': 'code'});
      final big = mapping('big', {'code': 'code', 'name': 'name'});
      final off = mapping('off', {'code': 'code', 'zip': 'city'});
      final best = bestSavedMapping(['Code', 'Name', 'x'], [small, big, off]);
      expect(best?.name, 'big');
      expect(bestSavedMapping(['x'], [small, big]), isNull);
      expect(bestSavedMapping(['code'], [mapping('empty', {})]), isNull);
    });

    test('a repeated header name is paired once', () {
      expect(sameNameFields(['code', 'Code', 'name'], entity), [
        'code',
        null,
        'name',
      ]);
    });

    test('columns are omitted only for an exact identity', () {
      expect(columnsToSend(['code', 'name'], ['code', 'name']), isNull);
      expect(
        columnsToSend(['code', 'name'], ['code', null])!.map((p) => p.field),
        ['code'],
      );
      expect(
        columnsToSend(['Code'], ['code'])!.single.column,
        'Code',
        reason: 'a differently written header is sent as a pair',
      );
    });

    test('the check finds a missing key and doubled fields', () {
      final c = checkMapping(['name', 'name'], entity);
      expect(c.keyMissing, isTrue);
      expect(c.duplicates, {'name'});
      expect(c.blocked, isTrue);
      expect(c.unmappedRequired, ['code']);
      expect(checkMapping(['code', 'name', 'city'], entity).blocked, isFalse);
    });
  });
}
