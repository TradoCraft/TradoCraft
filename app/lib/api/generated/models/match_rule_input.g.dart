// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_rule_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MatchRuleInput _$MatchRuleInputFromJson(Map<String, dynamic> json) =>
    MatchRuleInput(
      baselineAttributeKey: json['baseline_attribute_key'] as String,
      baselineTypeCode: json['baseline_type_code'] as String,
      name: json['name'] as String,
      operatorValue: Operator.fromJson(json['operator'] as String),
      productAttributeKey: json['product_attribute_key'] as String,
      active: json['active'] as bool?,
      sortOrder: (json['sort_order'] as num?)?.toInt(),
    );

Map<String, dynamic> _$MatchRuleInputToJson(MatchRuleInput instance) =>
    <String, dynamic>{
      'active': ?instance.active,
      'baseline_attribute_key': instance.baselineAttributeKey,
      'baseline_type_code': instance.baselineTypeCode,
      'name': instance.name,
      'operator': instance.operatorValue,
      'product_attribute_key': instance.productAttributeKey,
      'sort_order': ?instance.sortOrder,
    };
