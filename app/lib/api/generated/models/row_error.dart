// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'row_error.g.dart';

/// One problem in an import file.
@JsonSerializable()
class RowError {
  const RowError({
    required this.message,
    required this.row,
    this.column,
  });
  
  factory RowError.fromJson(Map<String, Object?> json) => _$RowErrorFromJson(json);
  
  /// Column name; null when the problem concerns the whole row.
  @JsonKey(includeIfNull: false)
  final String? column;
  final String message;

  /// Line in the file where the row starts (the header is line 1).
  final int row;

  Map<String, Object?> toJson() => _$RowErrorToJson(this);
}
