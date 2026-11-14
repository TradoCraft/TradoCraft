// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baseline_import_report.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BaselineImportReport _$BaselineImportReportFromJson(
  Map<String, dynamic> json,
) => BaselineImportReport(
  created: ImportCounts.fromJson(json['created'] as Map<String, dynamic>),
  dryRun: json['dry_run'] as bool,
  items: (json['items'] as List<dynamic>)
      .map((e) => ImportPreviewItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  replaced: (json['replaced'] as num).toInt(),
  sourceId: json['source_id'] as String,
  unmappedFields: (json['unmapped_fields'] as List<dynamic>)
      .map((e) => UnmappedField.fromJson(e as Map<String, dynamic>))
      .toList(),
  warnings: (json['warnings'] as List<dynamic>)
      .map((e) => ImportWarning.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$BaselineImportReportToJson(
  BaselineImportReport instance,
) => <String, dynamic>{
  'created': instance.created,
  'dry_run': instance.dryRun,
  'items': instance.items,
  'replaced': instance.replaced,
  'source_id': instance.sourceId,
  'unmapped_fields': instance.unmappedFields,
  'warnings': instance.warnings,
};
