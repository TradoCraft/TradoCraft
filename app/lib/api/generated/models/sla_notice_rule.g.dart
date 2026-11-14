// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sla_notice_rule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SlaNoticeRule _$SlaNoticeRuleFromJson(Map<String, dynamic> json) =>
    SlaNoticeRule(
      ackEnabled: json['ack_enabled'] as bool,
      breachEnabled: json['breach_enabled'] as bool,
      priority: json['priority'] as String?,
      teamId: json['team_id'] as String?,
    );

Map<String, dynamic> _$SlaNoticeRuleToJson(SlaNoticeRule instance) =>
    <String, dynamic>{
      'ack_enabled': instance.ackEnabled,
      'breach_enabled': instance.breachEnabled,
      'priority': ?instance.priority,
      'team_id': ?instance.teamId,
    };
