// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'column_pair.g.dart';

/// One field of a mapping, fed by a file column (`column`) or by a fixed value that every row.
/// gets (`value`, read like a text cell of the file): exactly one of the two. File columns are.
/// compared trimmed and case-insensitively. The old shape `{column, field}` is a pair with a.
/// column.
@JsonSerializable()
class ColumnPair {
  const ColumnPair({
    required this.field,
    this.column,
    this.value,
  });
  
  factory ColumnPair.fromJson(Map<String, Object?> json) => _$ColumnPairFromJson(json);
  
  /// The column as the file names it.
  @JsonKey(includeIfNull: false)
  final String? column;

  /// The entity's field it feeds.
  final String field;

  /// A fixed value for the field in every row, e.g. a date or the code of a list.
  @JsonKey(includeIfNull: false)
  final String? value;

  Map<String, Object?> toJson() => _$ColumnPairToJson(this);
}
