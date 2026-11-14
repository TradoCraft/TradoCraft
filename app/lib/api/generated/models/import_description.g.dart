// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_description.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportDescription _$ImportDescriptionFromJson(Map<String, dynamic> json) =>
    ImportDescription(
      auditEntity: json['audit_entity'] as String,
      columns: (json['columns'] as List<dynamic>)
          .map((e) => ImportColumn.fromJson(e as Map<String, dynamic>))
          .toList(),
      fileStem: json['file_stem'] as String,
      key: json['key'] as String,
      keyColumn: json['key_column'] as String,
    );

Map<String, dynamic> _$ImportDescriptionToJson(ImportDescription instance) =>
    <String, dynamic>{
      'audit_entity': instance.auditEntity,
      'columns': instance.columns,
      'file_stem': instance.fileStem,
      'key': instance.key,
      'key_column': instance.keyColumn,
    };
