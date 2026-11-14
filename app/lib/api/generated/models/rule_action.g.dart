// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RuleAction _$RuleActionFromJson(Map<String, dynamic> json) => RuleAction(
  kind: json['kind'] as String,
  address: json['address'] as String?,
  body: json['body'] as String?,
  flag: json['flag'] as bool?,
  periodHours: (json['period_hours'] as num?)?.toInt(),
  recipient: json['recipient'] as String?,
  subject: json['subject'] as String?,
  teamId: json['team_id'] as String?,
  userId: json['user_id'] as String?,
  value: json['value'] as String?,
);

Map<String, dynamic> _$RuleActionToJson(RuleAction instance) =>
    <String, dynamic>{
      'address': ?instance.address,
      'body': ?instance.body,
      'flag': ?instance.flag,
      'kind': instance.kind,
      'period_hours': ?instance.periodHours,
      'recipient': ?instance.recipient,
      'subject': ?instance.subject,
      'team_id': ?instance.teamId,
      'user_id': ?instance.userId,
      'value': ?instance.value,
    };
