// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'value_source.dart';

part 'value_result.g.dart';

@JsonSerializable()
class ValueResult {
  const ValueResult({
    required this.enabled,
    required this.kind,
    required this.name,
    required this.source,
    required this.value,
    required this.visible,
    this.calculated,
    this.options,
  });
  
  factory ValueResult.fromJson(Map<String, Object?> json) => _$ValueResultFromJson(json);
  
  /// What the formula gives, when the value is pinned.
  @JsonKey(includeIfNull: false)
  final dynamic calculated;
  final bool enabled;

  /// field | computed
  final String kind;
  final String name;

  /// Allowed values (choices, product pickers, alternatives of an overridable value).
  @JsonKey(includeIfNull: false)
  final List<dynamic>? options;
  final ValueSource source;
  final dynamic value;
  final bool visible;

  Map<String, Object?> toJson() => _$ValueResultToJson(this);
}
