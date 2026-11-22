import 'dart:typed_data';

/// Web: there is no file system to write to; downloads go through the browser.
Future<String?> platformDownloadsPath() async => null;

Future<String> writeUnique(String baseFolder, String relativePath, Uint8List bytes) =>
    throw UnsupportedError('Writing to a folder is not available in the browser.');

Future<void> openPathInSystem(String path) async {}

Future<bool> directoryExists(String path) async => false;
