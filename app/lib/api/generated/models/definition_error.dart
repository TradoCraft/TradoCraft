// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'definition_error.g.dart';

/// A problem in a definition.
@JsonSerializable()
class DefinitionError {
  const DefinitionError({
    required this.message,
    required this.path,
    this.end,
    this.start,
  });
  
  factory DefinitionError.fromJson(Map<String, Object?> json) => _$DefinitionErrorFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final int? end;
  final String message;

  /// JSON path of the offending element, e.g. `$.item_tables[0].computed[1].expr`.
  final String path;

  /// Character range within a formula or template, when the problem is in one.
  @JsonKey(includeIfNull: false)
  final int? start;

  Map<String, Object?> toJson() => _$DefinitionErrorToJson(this);
}
