// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'worker_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkerStatus _$WorkerStatusFromJson(Map<String, dynamic> json) => WorkerStatus(
  state: WorkerState.fromJson(json['state'] as String),
  ageSeconds: (json['age_seconds'] as num?)?.toInt(),
  host: json['host'] as String?,
  intervalSeconds: (json['interval_seconds'] as num?)?.toInt(),
  lastBeatAt: json['last_beat_at'] == null
      ? null
      : DateTime.parse(json['last_beat_at'] as String),
  lastOutage: json['last_outage'] == null
      ? null
      : Outage.fromJson(json['last_outage'] as Map<String, dynamic>),
  lateAfterSeconds: (json['late_after_seconds'] as num?)?.toInt(),
  startedAt: json['started_at'] == null
      ? null
      : DateTime.parse(json['started_at'] as String),
  version: json['version'] as String?,
);

Map<String, dynamic> _$WorkerStatusToJson(WorkerStatus instance) =>
    <String, dynamic>{
      'age_seconds': ?instance.ageSeconds,
      'host': ?instance.host,
      'interval_seconds': ?instance.intervalSeconds,
      'last_beat_at': ?instance.lastBeatAt?.toIso8601String(),
      'last_outage': ?instance.lastOutage,
      'late_after_seconds': ?instance.lateAfterSeconds,
      'started_at': ?instance.startedAt?.toIso8601String(),
      'state': instance.state,
      'version': ?instance.version,
    };
