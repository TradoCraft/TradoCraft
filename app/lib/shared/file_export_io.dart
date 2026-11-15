import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'file_export_path.dart';

/// The user's Downloads folder, or null where the platform has none (Android, iOS).
Future<String?> platformDownloadsPath() async {
  try {
    return (await getDownloadsDirectory())?.path;
  } on UnsupportedError {
    return null;
  }
}

/// Writes [bytes] to `<baseFolder>/<relativePath>`, creating folders, without ever overwriting an
/// existing file (a " (2)", " (3)" ... suffix is added instead). The final path is resolved and
/// checked to lie inside [baseFolder] (also through symbolic links); an absolute path or a `..`
/// throws [UnsafePathException]. Returns the path written.
Future<String> writeUnique(
  String baseFolder,
  String relativePath,
  Uint8List bytes,
) async {
  final segments = safeSegments(relativePath);
  final base = Directory(baseFolder);
  await base.create(recursive: true);
  final realBase = await base.resolveSymbolicLinks();
  final dirSegments = segments.sublist(0, segments.length - 1);
  // Walk down one level at a time from the resolved base. Nothing is created through a link and
  // every level is re-resolved after creation, so no write can leave the base.
  var current = realBase;
  for (final seg in dirSegments) {
    final next = p.join(current, seg);
    final type = FileSystemEntity.typeSync(next, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await Directory(next).create();
    } else if (type != FileSystemEntityType.directory) {
      // A symbolic link, a file or anything else.
      throw UnsafePathException(relativePath);
    }
    final real = await Directory(next).resolveSymbolicLinks();
    if (!p.isWithin(realBase, real)) {
      throw UnsafePathException(relativePath);
    }
    current = real;
  }
  final realTarget = current;
  final name = segments.last;
  for (var n = 1; ; n++) {
    final candidate = p.join(realTarget, n == 1 ? name : numberedName(name, n));
    if (FileSystemEntity.typeSync(candidate, followLinks: false) !=
        FileSystemEntityType.notFound) {
      continue;
    }
    try {
      // `exclusive` fails if the file appeared in the meantime.
      final f = await File(candidate).create(exclusive: true);
      await f.writeAsBytes(bytes, flush: true);
      return candidate;
    } on PathExistsException {
      continue;
    }
  }
}

/// Opens a file or folder with the system's default application.
Future<void> openPathInSystem(String path) async {
  await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
}
