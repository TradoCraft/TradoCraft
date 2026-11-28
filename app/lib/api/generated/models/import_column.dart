// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'column_kind.dart';

part 'import_column.g.dart';

/// One column of an entity's import file and export, in export order.
@JsonSerializable()
class ImportColumn {
  const ImportColumn({
    required this.kind,
    required this.name,
    required this.perLanguage,
    required this.requiredValue,
  });
  
  factory ImportColumn.fromJson(Map<String, Object?> json) => _$ImportColumnFromJson(json);
  
  final ColumnKind kind;

  /// The column name; for a per-language family the prefix (`name` for `name_nl`, `name_fr`).
  final String name;

  /// A family of columns `<name>_<language>`, one per ISO 639-1 language code (`name_nl`,.
  /// `name_fr`); a file has any number of them.
  @JsonKey(name: 'per_language')
  final bool perLanguage;

  /// Must have a value when the row creates a record (the key column is always required in the.
  /// file itself).
  /// The name has been replaced because it contains a keyword. Original name: `required`.
  @JsonKey(name: 'required')
  final bool requiredValue;

  Map<String, Object?> toJson() => _$ImportColumnToJson(this);
}
