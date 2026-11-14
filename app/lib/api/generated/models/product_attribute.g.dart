// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_attribute.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductAttribute _$ProductAttributeFromJson(Map<String, dynamic> json) =>
    ProductAttribute(
      key: json['key'] as String,
      kind: AttributeKind.fromJson(json['kind'] as String),
      value: json['value'] as String,
      unit: json['unit'] as String?,
      valueMax: json['value_max'] as String?,
      valueMin: json['value_min'] as String?,
    );

Map<String, dynamic> _$ProductAttributeToJson(ProductAttribute instance) =>
    <String, dynamic>{
      'key': instance.key,
      'kind': instance.kind,
      'unit': ?instance.unit,
      'value': instance.value,
      'value_max': ?instance.valueMax,
      'value_min': ?instance.valueMin,
    };
