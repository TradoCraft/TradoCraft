import 'dart:convert';

import '../../../app/api.dart';

/// Pure rules of the column mapping step (no widgets), kept apart so they can be tested alone.

/// File column names are compared trimmed and case-insensitively, as the server does.
String normalizeName(String s) => s.trim().toLowerCase();

/// The result of proposing a mapping: one field name (or null = ignore) per file column, and
/// the saved mapping it came from (null when columns were paired by name).
class MappingProposal {
  const MappingProposal(this.fields, this.from);
  final List<String?> fields;
  final ImportMapping? from;
}

/// The saved mapping whose file columns all occur in [header]; the one that covers most columns
/// when several do. Null when none fits.
ImportMapping? bestSavedMapping(
  List<String> header,
  List<ImportMapping> saved,
) {
  final present = {for (final h in header) normalizeName(h)};
  ImportMapping? best;
  for (final m in saved) {
    if (m.columns.isEmpty) continue;
    if (!m.columns.every((p) => present.contains(normalizeName(p.column)))) {
      continue;
    }
    if (best == null || m.columns.length > best.columns.length) best = m;
  }
  return best;
}

/// File columns paired with the field of the same name; a repeated header name is paired once,
/// so the proposal does not start with a conflict.
List<String?> sameNameFields(List<String> header, ImportDescription entity) {
  final byName = {
    for (final c in entity.columns) normalizeName(c.name): c.name,
  };
  final used = <String>{};
  return [
    for (final h in header)
      if (byName[normalizeName(h)] case final f? when used.add(f)) f else null,
  ];
}

MappingProposal proposeMapping({
  required List<String> header,
  required ImportDescription entity,
  required List<ImportMapping> saved,
}) {
  final m = bestSavedMapping(header, saved);
  if (m == null) return MappingProposal(sameNameFields(header, entity), null);
  return MappingProposal(fieldsFromMapping(header, entity, m), m);
}

/// The fields a saved mapping gives to the file columns in [header]; a column it does not name
/// is ignored, and so is a pair whose field the entity no longer has.
List<String?> fieldsFromMapping(
  List<String> header,
  ImportDescription entity,
  ImportMapping m,
) {
  final fieldNames = {for (final c in entity.columns) c.name};
  final byColumn = <String, String>{};
  for (final p in m.columns) {
    if (fieldNames.contains(p.field)) {
      byColumn.putIfAbsent(normalizeName(p.column), () => p.field);
    }
  }
  final used = <String>{};
  return [
    for (final h in header)
      if (byColumn[normalizeName(h)] case final f? when used.add(f))
        f
      else
        null,
  ];
}

/// What is wrong with, or missing from, a mapping.
class MappingCheck {
  const MappingCheck({
    required this.keyMissing,
    required this.duplicates,
    required this.unmapped,
    required this.unmappedRequired,
  });

  /// The key column is not chosen for any file column.
  final bool keyMissing;

  /// Fields chosen for more than one file column.
  final Set<String> duplicates;

  /// Fields without a file column.
  final List<String> unmapped;

  /// Fields without a file column that a new record needs.
  final List<String> unmappedRequired;

  bool get blocked => keyMissing || duplicates.isNotEmpty;
}

MappingCheck checkMapping(List<String?> fields, ImportDescription entity) {
  final seen = <String>{};
  final dup = <String>{};
  for (final f in fields) {
    if (f != null && !seen.add(f)) dup.add(f);
  }
  final unmapped = [
    for (final c in entity.columns)
      if (!seen.contains(c.name)) c.name,
  ];
  return MappingCheck(
    keyMissing: !seen.contains(entity.keyColumn),
    duplicates: dup,
    unmapped: unmapped,
    unmappedRequired: [
      for (final c in entity.columns)
        if (c.requiredValue && !seen.contains(c.name)) c.name,
    ],
  );
}

/// The pairs to send with a job: null (the header names our columns exactly, as ADR 0029) when
/// every file column is the field of the same name and nothing is ignored; the non-ignored
/// pairs otherwise. Equality is exact here: the strict header of the server is exact too.
List<ColumnPair>? columnsToSend(List<String> header, List<String?> fields) {
  var identity = true;
  for (var i = 0; i < header.length; i++) {
    if (fields[i] != header[i]) identity = false;
  }
  if (identity) return null;
  return [
    for (var i = 0; i < header.length; i++)
      if (fields[i] != null) ColumnPair(column: header[i], field: fields[i]!),
  ];
}

/// Identifies what a check was run for; Apply is possible only when it equals the current one.
String runSignature({
  required String fileId,
  required String entity,
  required String? sheet,
  required List<ColumnPair>? columns,
}) => jsonEncode([
  fileId,
  entity,
  sheet,
  columns == null
      ? null
      : [
          for (final p in columns) [p.column, p.field],
        ],
]);
