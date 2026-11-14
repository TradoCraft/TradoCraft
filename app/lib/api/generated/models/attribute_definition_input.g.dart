// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attribute_definition_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AttributeDefinitionInput _$AttributeDefinitionInputFromJson(
  Map<String, dynamic> json,
) => AttributeDefinitionInput(
  key: json['key'] as String,
  kind: DefinitionKind.fromJson(json['kind'] as String),
  label: json['label'] as String,
  active: json['active'] as bool?,
  options: (json['options'] as List<dynamic>?)
      ?.map((e) => SelectOption.fromJson(e as Map<String, dynamic>))
      .toList(),
  scope: json['scope'] as String?,
  sortOrder: (json['sort_order'] as num?)?.toInt(),
  unit: json['unit'] as String?,
);

Map<String, dynamic> _$AttributeDefinitionInputToJson(
  AttributeDefinitionInput instance,
) => <String, dynamic>{
  'active': ?instance.active,
  'key': instance.key,
  'kind': instance.kind,
  'label': instance.label,
  'options': ?instance.options,
  'scope': ?instance.scope,
  'sort_order': ?instance.sortOrder,
  'unit': ?instance.unit,
};
