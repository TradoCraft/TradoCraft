// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'stored_error.dart';

part 'import_job.g.dart';

/// One import run.
@JsonSerializable()
class ImportJob {
  const ImportJob({
    required this.created,
    required this.createdAt,
    required this.dryRun,
    required this.entity,
    required this.errorCount,
    required this.errors,
    required this.filename,
    required this.format,
    required this.id,
    required this.processedRows,
    required this.status,
    required this.totalRows,
    required this.unchanged,
    required this.updated,
    this.finishedAt,
    this.message,
    this.phase,
    this.requestedBy,
    this.requestedByName,
    this.sheet,
    this.startedAt,
  });
  
  factory ImportJob.fromJson(Map<String, Object?> json) => _$ImportJobFromJson(json);
  
  final int created;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'dry_run')
  final bool dryRun;
  final String entity;

  /// All errors found; `errors` holds the first 100 (the list endpoint none), the CSV all that.
  /// were kept (at most 10 000).
  @JsonKey(name: 'error_count')
  final int errorCount;
  final List<StoredError> errors;
  final String filename;
  @JsonKey(includeIfNull: false,name: 'finished_at')
  final DateTime? finishedAt;
  final String format;
  final String id;

  /// Why a `failed` job could not be carried out.
  @JsonKey(includeIfNull: false)
  final String? message;

  /// While running: `reading`, `validating` or `writing`.
  @JsonKey(includeIfNull: false)
  final String? phase;
  @JsonKey(name: 'processed_rows')
  final int processedRows;
  @JsonKey(includeIfNull: false,name: 'requested_by')
  final String? requestedBy;
  @JsonKey(includeIfNull: false,name: 'requested_by_name')
  final String? requestedByName;
  @JsonKey(includeIfNull: false)
  final String? sheet;
  @JsonKey(includeIfNull: false,name: 'started_at')
  final DateTime? startedAt;

  /// `queued`, `running`, `done`, `failed` or `cancelled`.
  final String status;
  @JsonKey(name: 'total_rows')
  final int totalRows;
  final int unchanged;
  final int updated;

  Map<String, Object?> toJson() => _$ImportJobToJson(this);
}
