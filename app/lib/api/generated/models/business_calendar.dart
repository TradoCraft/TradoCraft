// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'holiday.dart';
import 'working_hours.dart';

part 'business_calendar.g.dart';

@JsonSerializable()
class BusinessCalendar {
  const BusinessCalendar({
    required this.enabled,
    required this.holidays,
    required this.holidaysInherited,
    required this.hours,
    required this.inherited,
    required this.timeZone,
    this.teamId,
  });
  
  factory BusinessCalendar.fromJson(Map<String, Object?> json) => _$BusinessCalendarFromJson(json);
  
  /// When off, SLA times are plain elapsed time.
  final bool enabled;
  final List<Holiday> holidays;

  /// Set for a team: the company holidays count for it as well as the holidays listed (the team's own, or the company's when the team has no calendar of its own).
  @JsonKey(name: 'holidays_inherited')
  final bool holidaysInherited;
  final List<WorkingHours> hours;

  /// A team that has no calendar of its own: what is shown is the company's.
  final bool inherited;

  /// The team this calendar is for; absent for the company calendar.
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;

  /// An IANA name such as `Europe/Brussels`.
  @JsonKey(name: 'time_zone')
  final String timeZone;

  Map<String, Object?> toJson() => _$BusinessCalendarToJson(this);
}
