// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'operator.dart';

part 'match_rule.g.dart';

@JsonSerializable()
class MatchRule {
  const MatchRule({
    required this.active,
    required this.baselineAttributeKey,
    required this.baselineTypeCode,
    required this.createdAt,
    required this.id,
    required this.name,
    required this.operatorValue,
    required this.productAttributeKey,
    required this.sortOrder,
    required this.updatedAt,
  });
  
  factory MatchRule.fromJson(Map<String, Object?> json) => _$MatchRuleFromJson(json);
  
  final bool active;

  /// A `number` attribute of that type.
  @JsonKey(name: 'baseline_attribute_key')
  final String baselineAttributeKey;

  /// Code of the baseline item type whose items the rule reads.
  @JsonKey(name: 'baseline_type_code')
  final String baselineTypeCode;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  final String name;

  /// The name has been replaced because it contains a keyword. Original name: `operator`.
  @JsonKey(name: 'operator')
  final Operator operatorValue;

  /// A product attribute: `range` for `within_range`, `number` for `at_most` and `at_least`.
  @JsonKey(name: 'product_attribute_key')
  final String productAttributeKey;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$MatchRuleToJson(this);
}
