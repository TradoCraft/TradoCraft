// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'column_pair.dart';

part 'create_job.g.dart';

@JsonSerializable()
class CreateJob {
  const CreateJob({
    required this.dryRun,
    required this.entity,
    required this.fileId,
    this.columns,
    this.sheet,
  });
  
  factory CreateJob.fromJson(Map<String, Object?> json) => _$CreateJobFromJson(json);
  
  /// `file column -> field` pairs; absent or empty means the header names our columns exactly.
  @JsonKey(includeIfNull: false)
  final List<ColumnPair>? columns;

  /// Validate and count only.
  @JsonKey(name: 'dry_run')
  final bool dryRun;
  final String entity;
  @JsonKey(name: 'file_id')
  final String fileId;

  /// The sheet of a workbook; the first one when absent.
  @JsonKey(includeIfNull: false)
  final String? sheet;

  Map<String, Object?> toJson() => _$CreateJobToJson(this);
}
