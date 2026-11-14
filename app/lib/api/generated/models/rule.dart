// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'rule_action.dart';
import 'rule_conditions.dart';

part 'rule.g.dart';

@JsonSerializable()
class Rule {
  const Rule({
    required this.actions,
    required this.active,
    required this.conditions,
    required this.id,
    required this.name,
    required this.position,
    required this.stopOnMatch,
    required this.trigger,
    required this.updatedAt,
  });
  
  factory Rule.fromJson(Map<String, Object?> json) => _$RuleFromJson(json);
  
  final List<RuleAction> actions;
  final bool active;
  final RuleConditions conditions;
  final String id;
  final String name;

  /// Rules run in this order.
  final int position;

  /// Later rules are not looked at when this one matched.
  @JsonKey(name: 'stop_on_match')
  final bool stopOnMatch;

  /// created | updated | customer_replied
  final String trigger;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$RuleToJson(this);
}
