// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'work_log.g.dart';

@JsonSerializable()
class WorkLog {
  const WorkLog({
    required this.endedAt,
    required this.id,
    required this.kind,
    required this.minutes,
    required this.notes,
    required this.startedAt,
    required this.userId,
    required this.userName,
  });
  
  factory WorkLog.fromJson(Map<String, Object?> json) => _$WorkLogFromJson(json);
  
  @JsonKey(name: 'ended_at')
  final DateTime endedAt;
  final String id;

  /// work | travel
  final String kind;
  final int minutes;
  final String notes;
  @JsonKey(name: 'started_at')
  final DateTime startedAt;
  @JsonKey(name: 'user_id')
  final String userId;
  @JsonKey(name: 'user_name')
  final String userName;

  Map<String, Object?> toJson() => _$WorkLogToJson(this);
}
