// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'outage.dart';
import 'worker_state.dart';

part 'worker_status.g.dart';

/// The worker's heartbeat as administrators see it.
@JsonSerializable()
class WorkerStatus {
  const WorkerStatus({
    required this.state,
    this.ageSeconds,
    this.host,
    this.intervalSeconds,
    this.lastBeatAt,
    this.lastOutage,
    this.lateAfterSeconds,
    this.startedAt,
    this.version,
  });
  
  factory WorkerStatus.fromJson(Map<String, Object?> json) => _$WorkerStatusFromJson(json);
  
  /// Seconds since the last beat, by the database clock.
  @JsonKey(includeIfNull: false,name: 'age_seconds')
  final int? ageSeconds;
  @JsonKey(includeIfNull: false)
  final String? host;
  @JsonKey(includeIfNull: false,name: 'interval_seconds')
  final int? intervalSeconds;
  @JsonKey(includeIfNull: false,name: 'last_beat_at')
  final DateTime? lastBeatAt;

  /// The most recent period without beats that has ended.
  @JsonKey(includeIfNull: false,name: 'last_outage')
  final Outage? lastOutage;

  /// After how many seconds without a beat the worker counts as down.
  @JsonKey(includeIfNull: false,name: 'late_after_seconds')
  final int? lateAfterSeconds;

  /// When the worker process that wrote the last beat started.
  @JsonKey(includeIfNull: false,name: 'started_at')
  final DateTime? startedAt;
  final WorkerState state;
  @JsonKey(includeIfNull: false)
  final String? version;

  Map<String, Object?> toJson() => _$WorkerStatusToJson(this);
}
