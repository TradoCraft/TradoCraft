// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'work_centre_hours_slot.g.dart';

/// A block of working time of a work centre.
@JsonSerializable()
class WorkCentreHoursSlot {
  const WorkCentreHoursSlot({
    required this.endTime,
    required this.startTime,
    required this.weekday,
  });
  
  factory WorkCentreHoursSlot.fromJson(Map<String, Object?> json) => _$WorkCentreHoursSlotFromJson(json);
  
  @JsonKey(name: 'end_time')
  final String endTime;
  @JsonKey(name: 'start_time')
  final String startTime;

  /// 1 (Monday) to 7 (Sunday).
  final int weekday;

  Map<String, Object?> toJson() => _$WorkCentreHoursSlotToJson(this);
}
