// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rule_conditions.g.dart';

/// What a ticket must look like for a rule to apply. Every given condition has to hold; a list.
/// holds when the ticket has any one of its values. Empty conditions match every ticket.
@JsonSerializable()
class RuleConditions {
  const RuleConditions({
    this.categories,
    this.channels,
    this.customerId,
    this.customerLanguages,
    this.owner,
    this.priorities,
    this.senderDomain,
    this.statuses,
    this.subjectContains,
    this.tag,
    this.teamId,
  });
  
  factory RuleConditions.fromJson(Map<String, Object?> json) => _$RuleConditionsFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final List<String>? categories;

  /// email | portal | phone | manual | internal
  @JsonKey(includeIfNull: false)
  final List<String>? channels;
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;

  /// The language of the customer (nl, fr, en, de, es).
  @JsonKey(includeIfNull: false,name: 'customer_languages')
  final List<String>? customerLanguages;

  /// `empty` (nobody owns the ticket) or `set` (somebody does).
  @JsonKey(includeIfNull: false)
  final String? owner;
  @JsonKey(includeIfNull: false)
  final List<String>? priorities;

  /// The part of the contact's address after the `@`, case-insensitive.
  @JsonKey(includeIfNull: false,name: 'sender_domain')
  final String? senderDomain;
  @JsonKey(includeIfNull: false)
  final List<String>? statuses;

  /// Case-insensitive part of the subject.
  @JsonKey(includeIfNull: false,name: 'subject_contains')
  final String? subjectContains;
  @JsonKey(includeIfNull: false)
  final String? tag;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;

  Map<String, Object?> toJson() => _$RuleConditionsToJson(this);
}
