// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'working_hours.g.dart';

@JsonSerializable()
class WorkingHours {
  const WorkingHours({
    required this.endTime,
    required this.startTime,
    required this.weekday,
  });
  
  factory WorkingHours.fromJson(Map<String, Object?> json) => _$WorkingHoursFromJson(json);
  
  @JsonKey(name: 'end_time')
  final String endTime;

  /// `HH:MM`, local time.
  @JsonKey(name: 'start_time')
  final String startTime;

  /// 1 = Monday ... 7 = Sunday. A weekday that is not listed is closed.
  final int weekday;

  Map<String, Object?> toJson() => _$WorkingHoursToJson(this);
}
