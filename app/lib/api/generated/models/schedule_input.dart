// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'schedule_input.g.dart';

@JsonSerializable()
class ScheduleInput {
  const ScheduleInput({
    required this.scheduledEnd,
    required this.scheduledStart,
    required this.technicianIds,
  });
  
  factory ScheduleInput.fromJson(Map<String, Object?> json) => _$ScheduleInputFromJson(json);
  
  @JsonKey(name: 'scheduled_end')
  final DateTime scheduledEnd;
  @JsonKey(name: 'scheduled_start')
  final DateTime scheduledStart;

  /// Replaces the technicians of the job.
  @JsonKey(name: 'technician_ids')
  final List<String> technicianIds;

  Map<String, Object?> toJson() => _$ScheduleInputToJson(this);
}
