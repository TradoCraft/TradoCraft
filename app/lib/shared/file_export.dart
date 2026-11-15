import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import 'csv_transfer.dart' show CsvSaver, csvSaverProvider;
import 'file_export_path.dart';
import 'file_export_platform.dart' as platform;

export 'file_export_path.dart' show UnsafePathException;
export 'file_export_platform.dart' show defaultDownloadsFolder;

/// The folder files go to unless the caller names one; null when the platform has none.
typedef DownloadsFolder = Future<String?> Function();

/// Opens a file or folder in the system's file manager or default application.
typedef PathOpener = Future<void> Function(String path);

/// Writes bytes under a base folder and returns the path written (see `writeUnique`).
typedef FolderWriter = Future<String> Function(
  String baseFolder,
  String relativePath,
  Uint8List bytes,
);

/// Where a [FileExport] put a file. [path] is set when it was written to a folder; it is null when
/// the platform's own mechanism took over (browser download, share sheet), where the app does not
/// learn the location. [saved] is false when the person cancelled that mechanism.
class ExportedFile {
  const ExportedFile({required this.saved, this.path, this.baseFolder});
  final bool saved;
  final String? path;
  final String? baseFolder;
}

final downloadsFolderProvider = Provider<DownloadsFolder>(
  (_) => platform.defaultDownloadsFolder,
);

final pathOpenerProvider = Provider<PathOpener>((_) => platform.openPathInSystem);

/// The one place files leave the app. Replaced in tests through its providers.
class FileExport {
  FileExport({
    required this.downloads,
    required this.fallback,
    this.writer = platform.writeUnique,
  });

  final DownloadsFolder downloads;

  /// Used where there is no folder: the browser download or the share sheet.
  final CsvSaver fallback;
  final FolderWriter writer;

  /// Saves [bytes] as `<folder>/<relativePath>`: [baseFolder] when given, otherwise the Downloads
  /// folder. Folders are created, an existing file is never overwritten (" (2)" is appended), and
  /// a path that is absolute or contains `..` throws [UnsafePathException] before anything is
  /// written. Without any folder (browser, mobile) the file name goes to the platform's download
  /// or share mechanism.
  Future<ExportedFile> save(
    String relativePath,
    Uint8List bytes, {
    String? baseFolder,
  }) async {
    final segments = safeSegments(relativePath);
    final base = baseFolder ?? await downloads();
    if (base == null) {
      final ok = await fallback(segments.last, bytes);
      return ExportedFile(saved: ok);
    }
    final path = await writer(base, relativePath, bytes);
    return ExportedFile(saved: true, path: path, baseFolder: base);
  }
}

final fileExportProvider = Provider<FileExport>(
  (ref) => FileExport(
    downloads: ref.watch(downloadsFolderProvider),
    fallback: ref.watch(csvSaverProvider),
  ),
);

/// Saves a file through [FileExport] and tells the person: "Saved to PATH" with an Open action
/// when it was written to a folder, otherwise the file name (browser, share). Errors are thrown
/// for the caller's usual error handling. Returns null when the person cancelled.
Future<ExportedFile?> saveExport(
  BuildContext context,
  WidgetRef ref,
  String relativePath,
  Uint8List bytes, {
  String? baseFolder,
}) async {
  // Everything needed after the await is read first: the screen may be gone by then.
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final opener = ref.read(pathOpenerProvider);
  final result = await ref
      .read(fileExportProvider)
      .save(relativePath, bytes, baseFolder: baseFolder);
  if (!result.saved) return null;
  final path = result.path;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        path == null
            ? l.csvExported(safeSegments(relativePath).last)
            : l.fileSavedTo(path),
      ),
      action: path == null
          ? null
          : SnackBarAction(label: l.open, onPressed: () => opener(path)),
    ),
  );
  return result;
}
