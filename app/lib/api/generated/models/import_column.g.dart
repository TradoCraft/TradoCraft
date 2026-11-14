// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_column.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportColumn _$ImportColumnFromJson(Map<String, dynamic> json) => ImportColumn(
  kind: ColumnKind.fromJson(json['kind'] as String),
  name: json['name'] as String,
  requiredValue: json['required'] as bool,
);

Map<String, dynamic> _$ImportColumnToJson(ImportColumn instance) =>
    <String, dynamic>{
      'kind': instance.kind,
      'name': instance.name,
      'required': instance.requiredValue,
    };
