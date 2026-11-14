import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'csv_import_dialog.dart';

/// A file the person chose: its name and raw bytes.
typedef PickedFile = ({String name, Uint8List bytes});

/// Kept for the CSV-only users (the configurator tables).
typedef PickedCsv = PickedFile;

/// Lets the person choose a file; `null` when they cancel. Replaced in tests.
typedef CsvPicker = Future<PickedFile?> Function();

/// Saves or shares a file (the MIME type and the file type filter follow its extension: csv, xlsx,
/// ods, anything else is binary); `false` when the person cancelled. Replaced in tests. The name
/// says CSV for historical reasons: it saves every export, spreadsheets included.
typedef CsvSaver = Future<bool> Function(String filename, Uint8List bytes);

/// Runs an import (or only its dry run) of a CSV, XLSX or ODS file and reports what happened.
typedef CsvImporter = Future<ImportReport> Function(
  Uint8List bytes, {
  required bool dryRun,
});

/// Picks a CSV file only (the configurator tables).
final csvPickerProvider = Provider<CsvPicker>((_) => pickCsvFile);

/// Picks a CSV, XLSX or ODS file for an import.
final importFilePickerProvider = Provider<CsvPicker>((_) => pickImportFile);
final csvSaverProvider = Provider<CsvSaver>((_) => saveCsvFile);

const _csvTypes = XTypeGroup(
  label: 'CSV',
  extensions: ['csv'],
  mimeTypes: ['text/csv'],
  uniformTypeIdentifiers: ['public.comma-separated-values-text'],
);

const _xlsxTypes = XTypeGroup(
  label: 'Excel',
  extensions: ['xlsx', 'xlsm'],
  mimeTypes: [
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel.sheet.macroEnabled.12',
  ],
  uniformTypeIdentifiers: ['org.openxmlformats.spreadsheetml.sheet'],
);

const _odsTypes = XTypeGroup(
  label: 'OpenDocument',
  extensions: ['ods'],
  mimeTypes: ['application/vnd.oasis.opendocument.spreadsheet'],
  uniformTypeIdentifiers: ['org.oasis-open.opendocument.spreadsheet'],
);

/// The spreadsheet and CSV types an import accepts.
const importFileTypes = [_csvTypes, _xlsxTypes, _odsTypes];

Future<PickedFile?> _pick(List<XTypeGroup> types) async {
  final f = await openFile(acceptedTypeGroups: types);
  if (f == null) return null;
  return (name: f.name, bytes: await f.readAsBytes());
}

Future<PickedFile?> pickCsvFile() => _pick(const [_csvTypes]);

Future<PickedFile?> pickImportFile() => _pick(importFileTypes);

/// MIME type of a file we save, from its extension.
String mimeTypeFor(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  return switch (ext) {
    'csv' => 'text/csv',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
    'json' => 'application/json',
    _ => 'application/octet-stream',
  };
}

List<XTypeGroup> _saveTypesFor(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  return switch (ext) {
    'csv' => const [_csvTypes],
    'xlsx' => const [_xlsxTypes],
    'ods' => const [_odsTypes],
    _ => const [],
  };
}

/// Shares a file; replaced in tests.
typedef ShareFn = Future<ShareResult> Function(ShareParams params);

/// Opens the share sheet. `true` only when the share is confirmed; a dismissed sheet or an
/// unavailable result (the platform cannot say whether it happened) is not a confirmed save.
Future<bool> shareCsvFile(XFile file, String filename, {ShareFn? share}) async {
  final r = await (share ?? SharePlus.instance.share)(
    ShareParams(files: [file], fileNameOverrides: [filename]),
  );
  return r.status == ShareResultStatus.success;
}

/// Browser: a download. Android and iOS: the share sheet (there is no save dialog there).
/// Desktop: a "save as" dialog.
Future<bool> saveCsvFile(String filename, Uint8List bytes) async {
  final file = XFile.fromData(
    bytes,
    mimeType: mimeTypeFor(filename),
    name: filename,
  );
  if (kIsWeb) {
    await file.saveTo(filename);
    return true;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return shareCsvFile(file, filename);
    default:
      final target = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: _saveTypesFor(filename),
      );
      if (target == null) return false;
      await file.saveTo(target.path);
      return true;
  }
}

/// Posts the file as raw bytes (`application/octet-stream`); the server detects CSV, XLSX or ODS
/// from the content. A 422 carries the [ImportReport] with the row errors; it is returned like any
/// report so the caller shows the errors. Other failures are thrown.
Future<ImportReport> postImportFile(
  Dio dio,
  String path,
  Uint8List bytes, {
  required bool dryRun,
}) async {
  try {
    final res = await dio.post<Map<String, dynamic>>(
      path,
      data: bytes,
      queryParameters: {'dry_run': dryRun},
      options: Options(contentType: 'application/octet-stream'),
    );
    return ImportReport.fromJson(res.data!);
  } on DioException catch (e) {
    final data = e.response?.data;
    if (e.response?.statusCode == 422 &&
        data is Map &&
        data['errors'] is List) {
      return ImportReport.fromJson(Map<String, Object?>.from(data));
    }
    rethrow;
  }
}

/// "Import and export" menu for a list page: export as CSV, Excel or OpenDocument (needs
/// [canExport]) and import from such a file (needs [canImport]).
/// Renders nothing when neither is allowed.
class CsvMenu extends ConsumerWidget {
  const CsvMenu({
    super.key,
    required this.entity,
    required this.exportPath,
    required this.fileStem,
    required this.importer,
    required this.canExport,
    required this.canImport,
    required this.onImported,
  });

  /// Plural name of what is transferred, for titles ("customers").
  final String entity;
  final String exportPath;

  /// File name without extension; the format adds `.csv`, `.xlsx` or `.ods`.
  final String fileStem;
  final CsvImporter importer;
  final bool canExport;
  final bool canImport;
  final VoidCallback onImported;

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    Format format,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      final filename = '$fileStem.${format.json}';
      final bytes = await downloadBytes(
        ref.read(dioProvider),
        exportPath,
        queryParameters: {'format': format.json},
      );
      final saved = await ref.read(csvSaverProvider)(
        filename,
        Uint8List.fromList(bytes),
      );
      if (saved) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.csvExported(filename))),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.csvExportFailed(errorMessage(e)))),
      );
    }
  }

  Future<void> _import(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => CsvImportDialog(
        entity: entity,
        importer: importer,
        onImported: onImported,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canExport && !canImport) return const SizedBox.shrink();
    final l = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l.csvMenu,
      icon: const Icon(AppIcons.moreVert),
      onSelected: (v) => switch (v) {
        'csv' => _export(context, ref, Format.csv),
        'xlsx' => _export(context, ref, Format.xlsx),
        'ods' => _export(context, ref, Format.ods),
        _ => _import(context),
      },
      itemBuilder: (_) => [
        if (canExport) ...[
          for (final (value, label) in [
            ('csv', l.csvExportCsv),
            ('xlsx', l.csvExportXlsx),
            ('ods', l.csvExportOds),
          ])
            PopupMenuItem(
              value: value,
              child: ListTile(
                leading: const Icon(AppIcons.fileDownload),
                title: Text(label),
              ),
            ),
        ],
        if (canImport)
          PopupMenuItem(
            value: 'import',
            child: ListTile(
              leading: const Icon(AppIcons.fileUpload),
              title: Text(l.csvImport),
            ),
          ),
      ],
    );
  }
}
