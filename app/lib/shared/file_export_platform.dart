import 'package:flutter/foundation.dart';

import 'file_export_stub.dart' if (dart.library.io) 'file_export_io.dart' as io;

export 'file_export_stub.dart' if (dart.library.io) 'file_export_io.dart'
    show writeUnique, openPathInSystem, directoryExists;

/// The Downloads folder on desktop (Linux, Windows, macOS); null in the browser and on mobile,
/// which have no Downloads folder API (those keep the share sheet or the browser download).
Future<String?> defaultDownloadsFolder() async {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.windows ||
    TargetPlatform.macOS => io.platformDownloadsPath(),
    _ => null,
  };
}
