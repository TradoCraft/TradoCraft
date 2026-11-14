// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attribute_definition.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AttributeDefinition _$AttributeDefinitionFromJson(Map<String, dynamic> json) =>
    AttributeDefinition(
      active: json['active'] as bool,
      id: json['id'] as String,
      key: json['key'] as String,
      kind: DefinitionKind.fromJson(json['kind'] as String),
      label: json['label'] as String,
      options: (json['options'] as List<dynamic>)
          .map((e) => SelectOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      scope: json['scope'] as String,
      sortOrder: (json['sort_order'] as num).toInt(),
      unit: json['unit'] as String?,
    );

Map<String, dynamic> _$AttributeDefinitionToJson(
  AttributeDefinition instance,
) => <String, dynamic>{
  'active': instance.active,
  'id': instance.id,
  'key': instance.key,
  'kind': instance.kind,
  'label': instance.label,
  'options': instance.options,
  'scope': instance.scope,
  'sort_order': instance.sortOrder,
  'unit': ?instance.unit,
};
