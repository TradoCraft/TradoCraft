// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mapping_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MappingInput _$MappingInputFromJson(Map<String, dynamic> json) => MappingInput(
  columns: (json['columns'] as List<dynamic>)
      .map((e) => ColumnPair.fromJson(e as Map<String, dynamic>))
      .toList(),
  entity: json['entity'] as String,
  name: json['name'] as String,
);

Map<String, dynamic> _$MappingInputToJson(MappingInput instance) =>
    <String, dynamic>{
      'columns': instance.columns,
      'entity': instance.entity,
      'name': instance.name,
    };
