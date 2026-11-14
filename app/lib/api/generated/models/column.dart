// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'column_kind.dart';

part 'column.g.dart';

/// One column of an entity's import file and export, in export order.
@JsonSerializable()
class Column {
  const Column({
    required this.kind,
    required this.name,
    required this.requiredValue,
  });
  
  factory Column.fromJson(Map<String, Object?> json) => _$ColumnFromJson(json);
  
  final ColumnKind kind;
  final String name;

  /// Must have a value when the row creates a record (the key column is always required in the.
  /// file itself).
  /// The name has been replaced because it contains a keyword. Original name: `required`.
  @JsonKey(name: 'required')
  final bool requiredValue;

  Map<String, Object?> toJson() => _$ColumnToJson(this);
}
