// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'operator.dart';

part 'match_rule_input.g.dart';

/// A rule is created and replaced with the same fields.
@JsonSerializable()
class MatchRuleInput {
  const MatchRuleInput({
    required this.baselineAttributeKey,
    required this.baselineTypeCode,
    required this.name,
    required this.operatorValue,
    required this.productAttributeKey,
    this.active,
    this.sortOrder,
  });
  
  factory MatchRuleInput.fromJson(Map<String, Object?> json) => _$MatchRuleInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(name: 'baseline_attribute_key')
  final String baselineAttributeKey;
  @JsonKey(name: 'baseline_type_code')
  final String baselineTypeCode;

  /// Unique per company.
  final String name;

  /// The name has been replaced because it contains a keyword. Original name: `operator`.
  @JsonKey(name: 'operator')
  final Operator operatorValue;
  @JsonKey(name: 'product_attribute_key')
  final String productAttributeKey;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$MatchRuleInputToJson(this);
}
