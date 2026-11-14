// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'stored_error.g.dart';

/// One problem of an import, as stored with the job and shown to the person.
@JsonSerializable()
class StoredError {
  const StoredError({
    required this.message,
    required this.row,
    this.column,
  });
  
  factory StoredError.fromJson(Map<String, Object?> json) => _$StoredErrorFromJson(json);
  
  /// The column the problem concerns; null for the row as a whole.
  @JsonKey(includeIfNull: false)
  final String? column;
  final String message;

  /// Line (CSV) or sheet row where the problem is; the header is at its own row.
  final int row;

  Map<String, Object?> toJson() => _$StoredErrorToJson(this);
}
