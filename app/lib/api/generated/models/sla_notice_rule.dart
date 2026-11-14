// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'sla_notice_rule.g.dart';

@JsonSerializable()
class SlaNoticeRule {
  const SlaNoticeRule({
    required this.ackEnabled,
    required this.breachEnabled,
    this.priority,
    this.teamId,
  });
  
  factory SlaNoticeRule.fromJson(Map<String, Object?> json) => _$SlaNoticeRuleFromJson(json);
  
  /// Send an acknowledgement (ticket number and target response time) on creation.
  @JsonKey(name: 'ack_enabled')
  final bool ackEnabled;

  /// Send a notice when the first response time has run out without an answer.
  @JsonKey(name: 'breach_enabled')
  final bool breachEnabled;

  /// low | normal | high | urgent. Absent: every priority.
  @JsonKey(includeIfNull: false)
  final String? priority;

  /// Absent: every team.
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;

  Map<String, Object?> toJson() => _$SlaNoticeRuleToJson(this);
}
