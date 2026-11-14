// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'column.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Column _$ColumnFromJson(Map<String, dynamic> json) => Column(
  kind: ColumnKind.fromJson(json['kind'] as String),
  name: json['name'] as String,
  requiredValue: json['required'] as bool,
);

Map<String, dynamic> _$ColumnToJson(Column instance) => <String, dynamic>{
  'kind': instance.kind,
  'name': instance.name,
  'required': instance.requiredValue,
};
