// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'column_pair.g.dart';

/// One `file column -> field` pair. File columns are compared trimmed and case-insensitively.
@JsonSerializable()
class ColumnPair {
  const ColumnPair({
    required this.column,
    required this.field,
  });
  
  factory ColumnPair.fromJson(Map<String, Object?> json) => _$ColumnPairFromJson(json);
  
  /// The column as the file names it.
  final String column;

  /// The entity's field it feeds.
  final String field;

  Map<String, Object?> toJson() => _$ColumnPairToJson(this);
}
