// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_rule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MatchRule _$MatchRuleFromJson(Map<String, dynamic> json) => MatchRule(
  active: json['active'] as bool,
  baselineAttributeKey: json['baseline_attribute_key'] as String,
  baselineTypeCode: json['baseline_type_code'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  id: json['id'] as String,
  name: json['name'] as String,
  operatorValue: Operator.fromJson(json['operator'] as String),
  productAttributeKey: json['product_attribute_key'] as String,
  sortOrder: (json['sort_order'] as num).toInt(),
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$MatchRuleToJson(MatchRule instance) => <String, dynamic>{
  'active': instance.active,
  'baseline_attribute_key': instance.baselineAttributeKey,
  'baseline_type_code': instance.baselineTypeCode,
  'created_at': instance.createdAt.toIso8601String(),
  'id': instance.id,
  'name': instance.name,
  'operator': instance.operatorValue,
  'product_attribute_key': instance.productAttributeKey,
  'sort_order': instance.sortOrder,
  'updated_at': instance.updatedAt.toIso8601String(),
};
