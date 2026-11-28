// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'column_pair.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ColumnPair _$ColumnPairFromJson(Map<String, dynamic> json) => ColumnPair(
  field: json['field'] as String,
  column: json['column'] as String?,
  value: json['value'] as String?,
);

Map<String, dynamic> _$ColumnPairToJson(ColumnPair instance) =>
    <String, dynamic>{
      'column': ?instance.column,
      'field': instance.field,
      'value': ?instance.value,
    };
