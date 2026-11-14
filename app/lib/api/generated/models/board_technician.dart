// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'absence.dart';
import 'technician_hours.dart';
import 'user_skill.dart';

part 'board_technician.g.dart';

@JsonSerializable()
class BoardTechnician {
  const BoardTechnician({
    required this.absences,
    required this.displayName,
    required this.hoursAreDefault,
    required this.skills,
    required this.userId,
    required this.workingHours,
  });
  
  factory BoardTechnician.fromJson(Map<String, Object?> json) => _$BoardTechnicianFromJson(json);
  
  /// Absences touching the requested period.
  final List<Absence> absences;
  @JsonKey(name: 'display_name')
  final String displayName;

  /// True when `working_hours` are the company default.
  @JsonKey(name: 'hours_are_default')
  final bool hoursAreDefault;
  final List<UserSkill> skills;
  @JsonKey(name: 'user_id')
  final String userId;

  /// The hours that apply: their own, else the company default.
  @JsonKey(name: 'working_hours')
  final List<TechnicianHours> workingHours;

  Map<String, Object?> toJson() => _$BoardTechnicianToJson(this);
}
