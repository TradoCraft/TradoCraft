// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'working_hours.dart';

part 'calendar_input.g.dart';

@JsonSerializable()
class CalendarInput {
  const CalendarInput({
    required this.enabled,
    required this.hours,
    required this.timeZone,
  });
  
  factory CalendarInput.fromJson(Map<String, Object?> json) => _$CalendarInputFromJson(json);
  
  final bool enabled;
  final List<WorkingHours> hours;
  @JsonKey(name: 'time_zone')
  final String timeZone;

  Map<String, Object?> toJson() => _$CalendarInputToJson(this);
}
