// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_operation.g.dart';

/// One operation of a production order.
@JsonSerializable()
class ProductionOperation {
  const ProductionOperation({
    required this.id,
    required this.name,
    required this.notes,
    required this.plannedEnd,
    required this.plannedMinutes,
    required this.plannedStart,
    required this.position,
    required this.runMinutesPerUnit,
    required this.setupMinutes,
    required this.status,
    required this.workCentreCode,
    required this.workCentreId,
    required this.workCentreName,
    this.actualMinutes,
    this.completedAt,
    this.completedBy,
    this.completedByName,
    this.costRate,
    this.startedAt,
  });
  
  factory ProductionOperation.fromJson(Map<String, Object?> json) => _$ProductionOperationFromJson(json);
  
  /// Total minutes worked, recorded when the operation is finished.
  @JsonKey(includeIfNull: false,name: 'actual_minutes')
  final int? actualMinutes;
  @JsonKey(includeIfNull: false,name: 'completed_at')
  final DateTime? completedAt;

  /// Who finished (or, at completion of the order, closed) the operation.
  @JsonKey(includeIfNull: false,name: 'completed_by')
  final String? completedBy;
  @JsonKey(includeIfNull: false,name: 'completed_by_name')
  final String? completedByName;

  /// Cost of an hour at the work centre when the order was released or the operation moved.
  /// Only for users with the cost permission.
  @JsonKey(includeIfNull: false,name: 'cost_rate')
  final String? costRate;
  final String id;
  final String name;
  final String notes;
  @JsonKey(name: 'planned_end')
  final DateTime plannedEnd;

  /// Setup plus run time for the quantity of the order, rounded up to whole minutes.
  @JsonKey(name: 'planned_minutes')
  final int plannedMinutes;
  @JsonKey(name: 'planned_start')
  final DateTime plannedStart;
  final int position;
  @JsonKey(name: 'run_minutes_per_unit')
  final String runMinutesPerUnit;
  @JsonKey(name: 'setup_minutes')
  final int setupMinutes;
  @JsonKey(includeIfNull: false,name: 'started_at')
  final DateTime? startedAt;

  /// pending | in_progress | done | skipped
  final String status;
  @JsonKey(name: 'work_centre_code')
  final String workCentreCode;
  @JsonKey(name: 'work_centre_id')
  final String workCentreId;
  @JsonKey(name: 'work_centre_name')
  final String workCentreName;

  Map<String, Object?> toJson() => _$ProductionOperationToJson(this);
}
