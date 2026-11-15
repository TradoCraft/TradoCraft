/// Pure path rules of the file export helper (no `dart:io`, so the web build compiles them too).
library;

/// A relative path that is absolute, climbs out of its folder (`..`) or is otherwise unusable.
class UnsafePathException implements Exception {
  UnsafePathException(this.path);
  final String path;

  @override
  String toString() => 'Unsafe file path: $path';
}

/// The segments of [relative], which must be a relative path inside some base folder. Both `/` and
/// `\` separate segments. Rejects an empty path, a path starting with a separator or a drive
/// letter (absolute), a NUL character and any `..` segment. Empty and `.` segments are dropped.
List<String> safeSegments(String relative) {
  if (relative.isEmpty || relative.contains('\u0000')) {
    throw UnsafePathException(relative);
  }
  final normalized = relative.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      normalized.startsWith('~') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    throw UnsafePathException(relative);
  }
  final parts = <String>[];
  for (final s in normalized.split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..') throw UnsafePathException(relative);
    parts.add(s);
  }
  if (parts.isEmpty) throw UnsafePathException(relative);
  return parts;
}

/// [fileName] with " (n)" before the extension: `a.pdf` -> `a (2).pdf`; a dot-file or a name
/// without extension gets the suffix at the end.
String numberedName(String fileName, int n) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '$fileName ($n)';
  return '${fileName.substring(0, dot)} ($n)${fileName.substring(dot)}';
}
