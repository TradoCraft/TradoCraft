// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'export_plan_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExportPlanEntry _$ExportPlanEntryFromJson(Map<String, dynamic> json) =>
    ExportPlanEntry(
      format: RenderFormat.fromJson(json['format'] as String),
      lang: json['lang'] as String,
      relativePath: json['relative_path'] as String,
      zoneCode: json['zone_code'] as String,
      zoneId: json['zone_id'] as String,
      exportId: json['export_id'] as String?,
    );

Map<String, dynamic> _$ExportPlanEntryToJson(ExportPlanEntry instance) =>
    <String, dynamic>{
      'export_id': ?instance.exportId,
      'format': instance.format,
      'lang': instance.lang,
      'relative_path': instance.relativePath,
      'zone_code': instance.zoneCode,
      'zone_id': instance.zoneId,
    };
