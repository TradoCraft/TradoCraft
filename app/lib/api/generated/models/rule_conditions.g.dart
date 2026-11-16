// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_conditions.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RuleConditions _$RuleConditionsFromJson(Map<String, dynamic> json) =>
    RuleConditions(
      categories: (json['categories'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      channels: (json['channels'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      customerId: json['customer_id'] as String?,
      customerLanguages: (json['customer_languages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      owner: json['owner'] as String?,
      priorities: (json['priorities'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      senderDomain: json['sender_domain'] as String?,
      statuses: (json['statuses'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      subjectContains: json['subject_contains'] as String?,
      tag: json['tag'] as String?,
      teamId: json['team_id'] as String?,
      ticketLanguages: (json['ticket_languages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$RuleConditionsToJson(RuleConditions instance) =>
    <String, dynamic>{
      'categories': ?instance.categories,
      'channels': ?instance.channels,
      'customer_id': ?instance.customerId,
      'customer_languages': ?instance.customerLanguages,
      'owner': ?instance.owner,
      'priorities': ?instance.priorities,
      'sender_domain': ?instance.senderDomain,
      'statuses': ?instance.statuses,
      'subject_contains': ?instance.subjectContains,
      'tag': ?instance.tag,
      'team_id': ?instance.teamId,
      'ticket_languages': ?instance.ticketLanguages,
    };
