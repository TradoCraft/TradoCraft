// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stored_error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StoredError _$StoredErrorFromJson(Map<String, dynamic> json) => StoredError(
  message: json['message'] as String,
  row: (json['row'] as num).toInt(),
  column: json['column'] as String?,
);

Map<String, dynamic> _$StoredErrorToJson(StoredError instance) =>
    <String, dynamic>{
      'column': ?instance.column,
      'message': instance.message,
      'row': instance.row,
    };
