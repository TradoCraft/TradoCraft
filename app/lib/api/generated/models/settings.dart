// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'settings.g.dart';

@JsonSerializable()
class Settings {
  const Settings({
    required this.defaultJobMinutes,
    required this.timezone,
    required this.travelBufferMinutes,
  });
  
  factory Settings.fromJson(Map<String, Object?> json) => _$SettingsFromJson(json);
  
  /// Length assumed for a job without an end time.
  @JsonKey(name: 'default_job_minutes')
  final int defaultJobMinutes;

  /// Time zone of working hours and absences, e.g. `Europe/Brussels`.
  final String timezone;

  /// Minutes kept free between two consecutive jobs of a technician on the same day.
  @JsonKey(name: 'travel_buffer_minutes')
  final int travelBufferMinutes;

  Map<String, Object?> toJson() => _$SettingsToJson(this);
}
