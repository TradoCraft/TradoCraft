// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_mapping.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportMapping _$ImportMappingFromJson(Map<String, dynamic> json) =>
    ImportMapping(
      columns: (json['columns'] as List<dynamic>)
          .map((e) => ColumnPair.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      entity: json['entity'] as String,
      id: json['id'] as String,
      name: json['name'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$ImportMappingToJson(ImportMapping instance) =>
    <String, dynamic>{
      'columns': instance.columns,
      'created_at': instance.createdAt.toIso8601String(),
      'entity': instance.entity,
      'id': instance.id,
      'name': instance.name,
      'updated_at': instance.updatedAt.toIso8601String(),
    };
