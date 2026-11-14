// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'board_job.g.dart';

/// A job as the board shows it.
@JsonSerializable()
class BoardJob {
  const BoardJob({
    required this.city,
    required this.customerId,
    required this.customerName,
    required this.id,
    required this.kind,
    required this.number,
    required this.priority,
    required this.requiredSkillIds,
    required this.status,
    required this.technicianIds,
    required this.title,
    this.dueDate,
    this.scheduledEnd,
    this.scheduledStart,
  });
  
  factory BoardJob.fromJson(Map<String, Object?> json) => _$BoardJobFromJson(json);
  
  final String city;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(includeIfNull: false,name: 'due_date')
  final DateTime? dueDate;
  final String id;

  /// installation | maintenance | repair | inspection | other
  final String kind;
  final String number;

  /// low | normal | high | urgent
  final String priority;
  @JsonKey(name: 'required_skill_ids')
  final List<String> requiredSkillIds;
  @JsonKey(includeIfNull: false,name: 'scheduled_end')
  final DateTime? scheduledEnd;
  @JsonKey(includeIfNull: false,name: 'scheduled_start')
  final DateTime? scheduledStart;

  /// planned | in_progress | completed | cancelled
  final String status;
  @JsonKey(name: 'technician_ids')
  final List<String> technicianIds;
  final String title;

  Map<String, Object?> toJson() => _$BoardJobToJson(this);
}
