import 'dart:convert';

import '../../../app/api.dart';

/// Pure rules of the column mapping step (no widgets), kept apart so they can be tested alone.

/// File column names are compared trimmed and case-insensitively, as the server does.
String normalizeName(String s) => s.trim().toLowerCase();

/// The member of a per-language family (`name` for `name_fr`) that the file column [header]
/// names: the prefix, `_` and a two-letter code. The server checks the code against ISO 639-1.
String? familyField(ImportColumn column, String header) {
  if (!column.perLanguage) return null;
  final h = normalizeName(header);
  final prefix = '${column.name}_';
  if (!h.startsWith(prefix)) return null;
  final code = h.substring(prefix.length);
  return RegExp(r'^[a-z]{2}$').hasMatch(code) ? h : null;
}

/// Whether [field] is a field of [entity]: a column name or a member of a per-language family.
bool isEntityField(ImportDescription entity, String field) =>
    entity.columns.any(
      (c) =>
          (!c.perLanguage && c.name == field) || familyField(c, field) != null,
    );

/// The fields offered for the file column [header]: the plain columns, and of a per-language
/// family the member the header names.
List<String> columnFieldOptions(ImportDescription entity, String header) => [
  for (final c in entity.columns)
    if (!c.perLanguage) c.name else ?familyField(c, header),
];

/// The fields a fixed value can be given: every column that is not a per-language family.
List<ImportColumn> fixableColumns(ImportDescription entity) => [
  for (final c in entity.columns)
    if (!c.perLanguage) c,
];

/// The columns that together identify a record.
List<String> keyColumns(ImportDescription entity) {
  final keys = entity.keyColumns;
  return keys.isEmpty ? [entity.keyColumn] : keys;
}

/// The fixed values of a saved mapping whose fields the entity still has: field -> value.
Map<String, String> fixedFromMapping(
  ImportDescription entity,
  ImportMapping m,
) => {
  for (final p in m.columns)
    if (p.column == null && p.value != null && isEntityField(entity, p.field))
      p.field: p.value!,
};

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
    // Fixed values need no file column.
    if (!m.columns.every(
      (p) => p.column == null || present.contains(normalizeName(p.column!)),
    )) {
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
    for (final c in entity.columns)
      if (!c.perLanguage) normalizeName(c.name): c.name,
  };
  String? field(String h) =>
      byName[normalizeName(h)] ??
      entity.columns.map((c) => familyField(c, h)).nonNulls.firstOrNull;
  final used = <String>{};
  return [
    for (final h in header)
      if (field(h) case final f? when used.add(f)) f else null,
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
  final byColumn = <String, String>{};
  for (final p in m.columns) {
    final column = p.column;
    if (column != null && isEntityField(entity, p.field)) {
      byColumn.putIfAbsent(normalizeName(column), () => p.field);
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

  /// A key column has neither a file column nor a fixed value.
  final bool keyMissing;

  /// Fields chosen for more than one file column, or for a file column and a fixed value.
  final Set<String> duplicates;

  /// Fields without a file column.
  final List<String> unmapped;

  /// Fields without a file column that a new record needs.
  final List<String> unmappedRequired;

  bool get blocked => keyMissing || duplicates.isNotEmpty;
}

MappingCheck checkMapping(
  List<String?> fields,
  ImportDescription entity, {
  Map<String, String> fixed = const {},
}) {
  final seen = <String>{};
  final dup = <String>{};
  for (final f in fields) {
    if (f != null && !seen.add(f)) dup.add(f);
  }
  for (final f in fixed.keys) {
    if (!seen.add(f)) dup.add(f);
  }
  final unmapped = [
    for (final c in entity.columns)
      if (!c.perLanguage && !seen.contains(c.name)) c.name,
  ];
  return MappingCheck(
    keyMissing: keyColumns(entity).any((k) => !seen.contains(k)),
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
/// pairs otherwise, followed by the [fixed] values. Equality is exact here: the strict header of
/// the server is exact too.
List<ColumnPair>? columnsToSend(
  List<String> header,
  List<String?> fields, {
  Map<String, String> fixed = const {},
}) {
  var identity = fixed.isEmpty;
  for (var i = 0; i < header.length; i++) {
    if (fields[i] != header[i]) identity = false;
  }
  if (identity) return null;
  return [
    for (var i = 0; i < header.length; i++)
      if (fields[i] != null) ColumnPair(column: header[i], field: fields[i]!),
    for (final e in fixed.entries) ColumnPair(value: e.value, field: e.key),
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
          for (final p in columns) [p.column, p.value, p.field],
        ],
]);
