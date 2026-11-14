// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'suggestion_out.g.dart';

/// A suggestion as the API returns it.
@JsonSerializable()
class SuggestionOut {
  const SuggestionOut({
    required this.missingSkillIds,
    required this.scheduledEnd,
    required this.scheduledStart,
    required this.slackMinutes,
    required this.technicianId,
    required this.technicianName,
  });
  
  factory SuggestionOut.fromJson(Map<String, Object?> json) => _$SuggestionOutFromJson(json);
  
  @JsonKey(name: 'missing_skill_ids')
  final List<String> missingSkillIds;
  @JsonKey(name: 'scheduled_end')
  final DateTime scheduledEnd;
  @JsonKey(name: 'scheduled_start')
  final DateTime scheduledStart;
  @JsonKey(name: 'slack_minutes')
  final int slackMinutes;
  @JsonKey(name: 'technician_id')
  final String technicianId;
  @JsonKey(name: 'technician_name')
  final String technicianName;

  Map<String, Object?> toJson() => _$SuggestionOutToJson(this);
}
