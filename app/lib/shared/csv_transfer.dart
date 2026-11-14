import 'dart:convert';

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

/// A CSV file the person chose: its name and raw bytes.
typedef PickedCsv = ({String name, Uint8List bytes});

/// Lets the person choose a CSV file; `null` when they cancel. Replaced in tests.
typedef CsvPicker = Future<PickedCsv?> Function();

/// Saves or shares an exported CSV; `false` when the person cancelled. Replaced in tests.
typedef CsvSaver = Future<bool> Function(String filename, Uint8List bytes);

/// Runs a CSV import (or only its dry run) and reports what happened.
typedef CsvImporter = Future<ImportReport> Function(
  String csv, {
  required bool dryRun,
});

final csvPickerProvider = Provider<CsvPicker>((_) => pickCsvFile);
final csvSaverProvider = Provider<CsvSaver>((_) => saveCsvFile);

const _csvTypes = XTypeGroup(
  label: 'CSV',
  extensions: ['csv'],
  mimeTypes: ['text/csv'],
  uniformTypeIdentifiers: ['public.comma-separated-values-text'],
);

Future<PickedCsv?> pickCsvFile() async {
  final f = await openFile(acceptedTypeGroups: [_csvTypes]);
  if (f == null) return null;
  return (name: f.name, bytes: await f.readAsBytes());
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
  final file = XFile.fromData(bytes, mimeType: 'text/csv', name: filename);
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
        acceptedTypeGroups: [_csvTypes],
      );
      if (target == null) return false;
      await file.saveTo(target.path);
      return true;
  }
}

/// Posts the raw CSV (`text/csv`). A 422 carries the [ImportReport] with the row errors; it is
/// returned like any report so the caller shows the errors. Other failures are thrown.
Future<ImportReport> postCsv(
  Dio dio,
  String path,
  String csv, {
  required bool dryRun,
}) async {
  try {
    final res = await dio.post<Map<String, dynamic>>(
      path,
      data: csv,
      queryParameters: {'dry_run': dryRun},
      options: Options(contentType: 'text/csv; charset=utf-8'),
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

/// "CSV" menu for a list page: export (needs [canExport]) and import (needs [canImport]).
/// Renders nothing when neither is allowed.
class CsvMenu extends ConsumerWidget {
  const CsvMenu({
    super.key,
    required this.entity,
    required this.exportPath,
    required this.filename,
    required this.importer,
    required this.canExport,
    required this.canImport,
    required this.onImported,
  });

  /// Plural name of what is transferred, for titles ("customers").
  final String entity;
  final String exportPath;
  final String filename;
  final CsvImporter importer;
  final bool canExport;
  final bool canImport;
  final VoidCallback onImported;

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      final bytes = await downloadBytes(ref.read(dioProvider), exportPath);
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
      onSelected: (v) =>
          v == 'export' ? _export(context, ref) : _import(context),
      itemBuilder: (_) => [
        if (canExport)
          PopupMenuItem(
            value: 'export',
            child: ListTile(
              leading: const Icon(AppIcons.fileDownload),
              title: Text(l.csvExport),
            ),
          ),
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

/// Decodes a chosen file as UTF-8 text; throws [FormatException] for other encodings.
String decodeCsv(Uint8List bytes) => utf8.decode(bytes);
