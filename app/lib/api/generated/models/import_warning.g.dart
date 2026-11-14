// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_warning.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportWarning _$ImportWarningFromJson(Map<String, dynamic> json) =>
    ImportWarning(
      field: json['field'] as String,
      message: json['message'] as String,
      bell: json['bell'] as String?,
    );

Map<String, dynamic> _$ImportWarningToJson(ImportWarning instance) =>
    <String, dynamic>{
      'bell': ?instance.bell,
      'field': instance.field,
      'message': instance.message,
    };
