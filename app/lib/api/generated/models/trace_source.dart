// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'trace_source.g.dart';

/// Where a line comes from: the rule and, per contributing scope, the values it read.
@JsonSerializable()
class TraceSource {
  const TraceSource({
    required this.scope,
    required this.values,
    this.each,
    this.label,
  });
  
  factory TraceSource.fromJson(Map<String, Object?> json) => _$TraceSourceFromJson(json);
  
  /// The `for_each` element.
  @JsonKey(includeIfNull: false)
  final dynamic each;
  @JsonKey(includeIfNull: false)
  final String? label;

  /// `project`, `groups[Hall 1]` or `segments[0]`.
  final String scope;

  /// The names the rule's formulas read, with their values.
  final dynamic values;

  Map<String, Object?> toJson() => _$TraceSourceToJson(this);
}
