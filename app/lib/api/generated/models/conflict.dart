// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'conflict_kind.dart';
import 'severity.dart';

part 'conflict.g.dart';

@JsonSerializable()
class Conflict {
  const Conflict({
    required this.kind,
    required this.messageKey,
    required this.severity,
    this.otherJobId,
    this.skillId,
    this.technicianId,
  });
  
  factory Conflict.fromJson(Map<String, Object?> json) => _$ConflictFromJson(json);
  
  final ConflictKind kind;

  /// Translation key for the message, e.g. `planning.conflict.double_booked`.
  @JsonKey(name: 'message_key')
  final String messageKey;

  /// The other job, for a double booking.
  @JsonKey(includeIfNull: false,name: 'other_job_id')
  final String? otherJobId;
  final Severity severity;

  /// The missing skill, for a missing-skill conflict.
  @JsonKey(includeIfNull: false,name: 'skill_id')
  final String? skillId;

  /// The technician concerned; empty for conflicts of the job itself.
  @JsonKey(includeIfNull: false,name: 'technician_id')
  final String? technicianId;

  Map<String, Object?> toJson() => _$ConflictToJson(this);
}
