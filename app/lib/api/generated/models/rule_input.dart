// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'rule_action.dart';
import 'rule_conditions.dart';

part 'rule_input.g.dart';

@JsonSerializable()
class RuleInput {
  const RuleInput({
    required this.actions,
    required this.name,
    required this.trigger,
    this.active,
    this.conditions,
    this.stopOnMatch,
  });
  
  factory RuleInput.fromJson(Map<String, Object?> json) => _$RuleInputFromJson(json);
  
  final List<RuleAction> actions;
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false)
  final RuleConditions? conditions;
  final String name;
  @JsonKey(includeIfNull: false,name: 'stop_on_match')
  final bool? stopOnMatch;
  final String trigger;

  Map<String, Object?> toJson() => _$RuleInputToJson(this);
}
