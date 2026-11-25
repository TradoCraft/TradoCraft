// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mrp_run.g.dart';

/// A planning run.
@JsonSerializable()
class MrpRun {
  const MrpRun({
    required this.createdAt,
    required this.horizonDays,
    required this.id,
    required this.number,
    required this.plannedOn,
    required this.proposals,
  });
  
  factory MrpRun.fromJson(Map<String, Object?> json) => _$MrpRunFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'horizon_days')
  final int horizonDays;
  final String id;
  final String number;

  /// The day the plan started from.
  @JsonKey(name: 'planned_on')
  final DateTime plannedOn;

  /// How many proposals it made.
  final int proposals;

  Map<String, Object?> toJson() => _$MrpRunToJson(this);
}
