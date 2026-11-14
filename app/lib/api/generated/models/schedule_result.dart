// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'board_job.dart';
import 'conflict.dart';

part 'schedule_result.g.dart';

@JsonSerializable()
class ScheduleResult {
  const ScheduleResult({
    required this.applied,
    required this.conflicts,
    this.job,
  });
  
  factory ScheduleResult.fromJson(Map<String, Object?> json) => _$ScheduleResultFromJson(json);
  
  /// False for a dry run.
  final bool applied;
  final List<Conflict> conflicts;

  /// The job after the change.
  @JsonKey(includeIfNull: false)
  final BoardJob? job;

  Map<String, Object?> toJson() => _$ScheduleResultToJson(this);
}
