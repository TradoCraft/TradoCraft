// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'equipment_job.g.dart';

@JsonSerializable()
class EquipmentJob {
  const EquipmentJob({
    required this.id,
    required this.kind,
    required this.number,
    required this.status,
    required this.title,
    this.completedAt,
    this.scheduledStart,
  });
  
  factory EquipmentJob.fromJson(Map<String, Object?> json) => _$EquipmentJobFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'completed_at')
  final DateTime? completedAt;
  final String id;
  final String kind;
  final String number;
  @JsonKey(includeIfNull: false,name: 'scheduled_start')
  final DateTime? scheduledStart;
  final String status;
  final String title;

  Map<String, Object?> toJson() => _$EquipmentJobToJson(this);
}
