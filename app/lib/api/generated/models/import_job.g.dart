// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_job.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportJob _$ImportJobFromJson(Map<String, dynamic> json) => ImportJob(
  created: (json['created'] as num).toInt(),
  createdAt: DateTime.parse(json['created_at'] as String),
  dryRun: json['dry_run'] as bool,
  entity: json['entity'] as String,
  errorCount: (json['error_count'] as num).toInt(),
  errors: (json['errors'] as List<dynamic>)
      .map((e) => StoredError.fromJson(e as Map<String, dynamic>))
      .toList(),
  filename: json['filename'] as String,
  format: json['format'] as String,
  id: json['id'] as String,
  processedRows: (json['processed_rows'] as num).toInt(),
  status: json['status'] as String,
  totalRows: (json['total_rows'] as num).toInt(),
  unchanged: (json['unchanged'] as num).toInt(),
  updated: (json['updated'] as num).toInt(),
  finishedAt: json['finished_at'] == null
      ? null
      : DateTime.parse(json['finished_at'] as String),
  message: json['message'] as String?,
  phase: json['phase'] as String?,
  requestedBy: json['requested_by'] as String?,
  requestedByName: json['requested_by_name'] as String?,
  sheet: json['sheet'] as String?,
  startedAt: json['started_at'] == null
      ? null
      : DateTime.parse(json['started_at'] as String),
);

Map<String, dynamic> _$ImportJobToJson(ImportJob instance) => <String, dynamic>{
  'created': instance.created,
  'created_at': instance.createdAt.toIso8601String(),
  'dry_run': instance.dryRun,
  'entity': instance.entity,
  'error_count': instance.errorCount,
  'errors': instance.errors,
  'filename': instance.filename,
  'finished_at': ?instance.finishedAt?.toIso8601String(),
  'format': instance.format,
  'id': instance.id,
  'message': ?instance.message,
  'phase': ?instance.phase,
  'processed_rows': instance.processedRows,
  'requested_by': ?instance.requestedBy,
  'requested_by_name': ?instance.requestedByName,
  'sheet': ?instance.sheet,
  'started_at': ?instance.startedAt?.toIso8601String(),
  'status': instance.status,
  'total_rows': instance.totalRows,
  'unchanged': instance.unchanged,
  'updated': instance.updated,
};
