import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/customers/customers_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/csv_import_dialog.dart';
import 'package:tradocraft_app/shared/csv_transfer.dart';

import 'fake_http.dart';

Map<String, Object?> report({
  int created = 0,
  int updated = 0,
  int unchanged = 0,
  List<Map<String, Object?>> errors = const [],
}) => {
  'created': created,
  'updated': updated,
  'unchanged': unchanged,
  'errors': errors,
};

PickedFile csv(String text, {String name = 'customers.csv'}) =>
    (name: name, bytes: Uint8List.fromList(utf8.encode(text)));

/// A binary spreadsheet: zip magic bytes, not valid UTF-8.
PickedFile sheet(String name) => (
  name: name,
  bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0xE9, 0xFF, 0x00, 0x80]),
);

/// A fake server whose import answers [dryRun] or [real] depending on `dry_run`.
FakeHttp http({
  List<String> perms = const ['customers.read', 'customers.write'],
  required Object? Function() dryRun,
  Object? Function()? real,
}) {
  late final FakeHttp h;
  h = FakeHttp({
    'GET /api/v1/me': (_) => meJson(perms),
    'GET /api/v1/customers': (_) => {'items': [], 'total': 0},
    'GET /api/v1/customers/export': (_) => 'code;name\r\nC1;Acme\r\n',
    'POST /api/v1/customers/import': (_) =>
        h.queries.last['dry_run'] == true ? dryRun() : (real ?? dryRun)(),
  });
  return h;
}

Future<void> pumpPage(
  WidgetTester tester,
  FakeHttp h, {
  PickedFile? picked,
  CsvSaver? saver,
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(h)),
        importFilePickerProvider.overrideWithValue(() async => picked),
        if (saver != null) csvSaverProvider.overrideWithValue(saver),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CustomersPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openImport(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Import and export'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Import from file'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester) async {
  await tester.tap(find.text('Choose file'));
  await tester.pumpAndSettle();
}

Finder importButton() => find.widgetWithText(FilledButton, 'Import');

void main() {
  testWidgets('menu shows both entries with read and write permission', (
    tester,
  ) async {
    await pumpPage(tester, http(dryRun: () => report()));
    await tester.tap(find.byTooltip('Import and export'));
    await tester.pumpAndSettle();
    expect(find.text('Export as CSV'), findsOneWidget);
    expect(find.text('Export as Excel (XLSX)'), findsOneWidget);
    expect(find.text('Export as OpenDocument (ODS)'), findsOneWidget);
    expect(find.text('Import from file'), findsOneWidget);
  });

  testWidgets('without write permission only export is offered', (
    tester,
  ) async {
    await pumpPage(
      tester,
      http(perms: ['customers.read'], dryRun: () => report()),
    );
    await tester.tap(find.byTooltip('Import and export'));
    await tester.pumpAndSettle();
    expect(find.text('Export as CSV'), findsOneWidget);
    expect(find.text('Import from file'), findsNothing);
  });

  testWidgets('without any permission there is no menu', (tester) async {
    await pumpPage(tester, http(perms: [], dryRun: () => report()));
    expect(find.byTooltip('Import and export'), findsNothing);
  });

  testWidgets('export downloads the file and hands it to the saver', (
    tester,
  ) async {
    String? savedName;
    String? savedText;
    final h = http(dryRun: () => report());
    await pumpPage(
      tester,
      h,
      saver: (name, bytes) async {
        savedName = name;
        savedText = utf8.decode(bytes);
        return true;
      },
    );
    await tester.tap(find.byTooltip('Import and export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export as CSV'));
    await tester.pumpAndSettle();
    expect(savedName, 'customers.csv');
    expect(savedText, contains('C1;Acme'));
    expect(h.queries.last['format'], 'csv');
    expect(find.text('Saved customers.csv'), findsOneWidget);
  });

  for (final (label, format) in [
    ('Export as Excel (XLSX)', 'xlsx'),
    ('Export as OpenDocument (ODS)', 'ods'),
  ]) {
    testWidgets('export as $format asks for that format and names the file', (
      tester,
    ) async {
      String? savedName;
      final h = http(dryRun: () => report());
      await pumpPage(
        tester,
        h,
        saver: (name, bytes) async {
          savedName = name;
          return true;
        },
      );
      await tester.tap(find.byTooltip('Import and export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(h.requests.last, 'GET /api/v1/customers/export');
      expect(h.queries.last['format'], format);
      expect(savedName, 'customers.$format');
    });
  }

  test('saved files get the MIME type of their extension', () {
    expect(mimeTypeFor('a.csv'), 'text/csv');
    expect(mimeTypeFor('a.XLSX'), contains('spreadsheetml'));
    expect(mimeTypeFor('a.ods'), contains('opendocument'));
    expect(mimeTypeFor('a.bin'), 'application/octet-stream');
    expect(mimeTypeFor('noext'), 'application/octet-stream');
  });

  testWidgets('dry run shows the counts and enables Import', (tester) async {
    final h = http(dryRun: () => report(created: 2, updated: 3, unchanged: 4));
    await pumpPage(tester, h, picked: csv('code;name\nC1;A\n'));
    await openImport(tester);
    expect(
      tester.widget<FilledButton>(importButton()).onPressed,
      isNull,
      reason: 'no file chosen yet',
    );
    await choose(tester);
    expect(find.text('To create'), findsOneWidget);
    expect(find.text('To update'), findsOneWidget);
    expect(find.text('Unchanged'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(tester.widget<FilledButton>(importButton()).onPressed, isNotNull);
    // Only the dry run has been sent, with the raw bytes of the file.
    expect(h.queries.last['dry_run'], true);
    expect(
      h.bodies['POST /api/v1/customers/import'],
      utf8.encode('code;name\nC1;A\n'),
    );
    expect(h.requests.where((r) => r.contains('import')).length, 1);
  });

  testWidgets('row errors (422) are listed and Import stays disabled', (
    tester,
  ) async {
    final h = http(
      dryRun: () => FakeStatus(
        422,
        report(
          errors: [
            {'row': 3, 'column': 'vat_number', 'message': 'Invalid VAT'},
            {'row': 5, 'message': 'Duplicate code'},
          ],
        ),
      ),
    );
    await pumpPage(tester, h, picked: csv('code;name\nC1;A\n'));
    await openImport(tester);
    await choose(tester);
    expect(
      find.text('2 problems found. Nothing has been imported.'),
      findsOneWidget,
    );
    expect(find.text('Invalid VAT'), findsOneWidget);
    expect(find.text('Row 3, column vat_number'), findsOneWidget);
    expect(find.text('Duplicate code'), findsOneWidget);
    expect(find.text('Row 5'), findsOneWidget);
    expect(tester.widget<FilledButton>(importButton()).onPressed, isNull);
  });

  testWidgets('long error lists are capped', (tester) async {
    final h = http(
      dryRun: () => FakeStatus(
        422,
        report(
          errors: [
            for (var i = 1; i <= 130; i++) {'row': i, 'message': 'Bad $i'},
          ],
        ),
      ),
    );
    await pumpPage(tester, h, picked: csv('code\nC1\n'));
    await openImport(tester);
    await choose(tester);
    await tester.scrollUntilVisible(
      find.text('and 30 more'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('and 30 more'), findsOneWidget);
  });

  testWidgets('a clean dry run then Import runs the real import', (
    tester,
  ) async {
    final h = http(
      dryRun: () => report(created: 1),
      real: () => report(created: 1),
    );
    await pumpPage(tester, h, picked: csv('code;name\nC1;A\n'));
    await openImport(tester);
    await choose(tester);
    final listCalls = h.requests.where((r) => r == 'GET /api/v1/customers');
    final before = listCalls.length;
    await tester.tap(importButton());
    await tester.pumpAndSettle();
    expect(h.queries.where((q) => q['dry_run'] == false), hasLength(1));
    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    // The list was reloaded.
    expect(
      h.requests.where((r) => r == 'GET /api/v1/customers').length,
      greaterThan(before),
    );
  });

  testWidgets('an empty file is refused without calling the server', (
    tester,
  ) async {
    final h = http(dryRun: () => report());
    await pumpPage(tester, h, picked: csv(''));
    await openImport(tester);
    await choose(tester);
    expect(find.text('The file is empty.'), findsOneWidget);
    expect(h.requests.where((r) => r.contains('import')), isEmpty);
    expect(tester.widget<FilledButton>(importButton()).onPressed, isNull);
  });

  testWidgets('a spreadsheet is sent as raw bytes, whatever its encoding', (
    tester,
  ) async {
    final h = http(
      dryRun: () => report(created: 1),
      real: () => report(created: 1),
    );
    final file = sheet('customers.xlsx');
    await pumpPage(tester, h, picked: file);
    await openImport(tester);
    await choose(tester);
    expect(find.text('customers.xlsx'), findsOneWidget);
    expect(h.bodies['POST /api/v1/customers/import'], file.bytes);
    expect(tester.widget<FilledButton>(importButton()).onPressed, isNotNull);
    await tester.tap(importButton());
    await tester.pumpAndSettle();
    expect(h.bodies['POST /api/v1/customers/import'], file.bytes);
    expect(h.queries.where((q) => q['dry_run'] == false), hasLength(1));
    // The list-page dialog always reads the first sheet.
    expect(h.queries.every((q) => !q.containsKey('sheet')), isTrue);
    expect(find.text('Import complete'), findsOneWidget);
  });

  testWidgets('the help names the three formats and the first sheet', (
    tester,
  ) async {
    await pumpPage(tester, http(dryRun: () => report()));
    await openImport(tester);
    expect(find.textContaining('Excel (XLSX)'), findsOneWidget);
    expect(find.textContaining('OpenDocument (ODS)'), findsOneWidget);
    expect(find.textContaining('first sheet'), findsOneWidget);
    expect(find.text('Import: Customers'), findsOneWidget);
  });

  testWidgets('an unknown or ambiguous sheet comes back as a row error', (
    tester,
  ) async {
    final h = http(
      dryRun: () => FakeStatus(
        422,
        report(
          errors: [
            {'row': 0, 'message': 'Unknown sheet "x". Sheets: A, B'},
          ],
        ),
      ),
    );
    await pumpPage(tester, h, picked: sheet('c.ods'));
    await openImport(tester);
    await choose(tester);
    expect(find.textContaining('Unknown sheet'), findsOneWidget);
    expect(tester.widget<FilledButton>(importButton()).onPressed, isNull);
  });

  testWidgets('a server failure on the dry run shows its message', (
    tester,
  ) async {
    final h = http(
      dryRun: () => FakeStatus(500, {'error': 'x', 'message': 'Boom'}),
    );
    await pumpPage(tester, h, picked: csv('code\nC1\n'));
    await openImport(tester);
    await choose(tester);
    expect(find.text('Boom'), findsOneWidget);
    expect(tester.widget<FilledButton>(importButton()).onPressed, isNull);
  });

  testWidgets('onImported runs after the import completes even if dismissed', (
    tester,
  ) async {
    final gate = Completer<void>();
    var imported = 0;
    bool? result = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importFilePickerProvider.overrideWithValue(
            () async => csv('code;name\nC1;A\n'),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => CsvImportDialog(
                    entity: 'customers',
                    importer: (text, {required dryRun}) async {
                      if (!dryRun) await gate.future;
                      return ImportReport.fromJson(report(created: 1));
                    },
                    onImported: () => imported++,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await choose(tester);
    await tester.tap(importButton());
    await tester.pump();
    // Dismiss through the barrier while the write is in flight.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CsvImportDialog), findsNothing);
    expect(result, isNull);
    expect(imported, 0);
    gate.complete();
    await tester.pumpAndSettle();
    expect(imported, 1);
  });

  testWidgets('a failed import does not call onImported', (tester) async {
    var imported = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importFilePickerProvider.overrideWithValue(
            () async => csv('code;name\nC1;A\n'),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CsvImportDialog(
              entity: 'customers',
              importer: (text, {required dryRun}) async {
                if (dryRun) return ImportReport.fromJson(report(created: 1));
                throw Exception('boom');
              },
              onImported: () => imported++,
            ),
          ),
        ),
      ),
    );
    await choose(tester);
    await tester.tap(importButton());
    await tester.pumpAndSettle();
    expect(imported, 0);
  });

  group('shareCsvFile', () {
    final file = XFile.fromData(Uint8List(1), name: 'a.csv');
    Future<bool> run(ShareResultStatus s) =>
        shareCsvFile(file, 'a.csv', share: (_) async => ShareResult('', s));
    test('only a confirmed share counts as saved', () async {
      expect(await run(ShareResultStatus.success), isTrue);
      expect(await run(ShareResultStatus.dismissed), isFalse);
      expect(await run(ShareResultStatus.unavailable), isFalse);
    });
  });
}
