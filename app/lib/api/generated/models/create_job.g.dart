// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_job.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateJob _$CreateJobFromJson(Map<String, dynamic> json) => CreateJob(
  dryRun: json['dry_run'] as bool,
  entity: json['entity'] as String,
  fileId: json['file_id'] as String,
  columns: (json['columns'] as List<dynamic>?)
      ?.map((e) => ColumnPair.fromJson(e as Map<String, dynamic>))
      .toList(),
  sheet: json['sheet'] as String?,
);

Map<String, dynamic> _$CreateJobToJson(CreateJob instance) => <String, dynamic>{
  'columns': ?instance.columns,
  'dry_run': instance.dryRun,
  'entity': instance.entity,
  'file_id': instance.fileId,
  'sheet': ?instance.sheet,
};
