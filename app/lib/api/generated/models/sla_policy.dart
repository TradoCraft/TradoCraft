// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'sla_policy.g.dart';

@JsonSerializable()
class SlaPolicy {
  const SlaPolicy({
    required this.firstResponseMinutes,
    required this.priority,
    required this.resolutionMinutes,
  });
  
  factory SlaPolicy.fromJson(Map<String, Object?> json) => _$SlaPolicyFromJson(json);
  
  @JsonKey(name: 'first_response_minutes')
  final int firstResponseMinutes;

  /// low | normal | high | urgent
  final String priority;
  @JsonKey(name: 'resolution_minutes')
  final int resolutionMinutes;

  Map<String, Object?> toJson() => _$SlaPolicyToJson(this);
}
