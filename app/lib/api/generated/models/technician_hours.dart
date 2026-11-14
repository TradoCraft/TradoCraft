// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'technician_hours.g.dart';

@JsonSerializable()
class TechnicianHours {
  const TechnicianHours({
    required this.endTime,
    required this.id,
    required this.startTime,
    required this.weekday,
    this.userId,
  });
  
  factory TechnicianHours.fromJson(Map<String, Object?> json) => _$TechnicianHoursFromJson(json);
  
  @JsonKey(name: 'end_time')
  final String endTime;
  final String id;
  @JsonKey(name: 'start_time')
  final String startTime;

  /// Empty for the company default.
  @JsonKey(includeIfNull: false,name: 'user_id')
  final String? userId;

  /// 1 = Monday ... 7 = Sunday.
  final int weekday;

  Map<String, Object?> toJson() => _$TechnicianHoursToJson(this);
}
