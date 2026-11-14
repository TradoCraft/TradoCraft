// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_preview_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportPreviewItem _$ImportPreviewItemFromJson(Map<String, dynamic> json) =>
    ImportPreviewItem(
      name: json['name'] as String,
      typeCode: json['type_code'] as String,
      values: json['values'],
    );

Map<String, dynamic> _$ImportPreviewItemToJson(ImportPreviewItem instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type_code': instance.typeCode,
      'values': instance.values,
    };
