// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_operation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionOperation _$ProductionOperationFromJson(Map<String, dynamic> json) =>
    ProductionOperation(
      id: json['id'] as String,
      name: json['name'] as String,
      notes: json['notes'] as String,
      plannedEnd: DateTime.parse(json['planned_end'] as String),
      plannedMinutes: (json['planned_minutes'] as num).toInt(),
      plannedStart: DateTime.parse(json['planned_start'] as String),
      position: (json['position'] as num).toInt(),
      runMinutesPerUnit: json['run_minutes_per_unit'] as String,
      setupMinutes: (json['setup_minutes'] as num).toInt(),
      status: json['status'] as String,
      workCentreCode: json['work_centre_code'] as String,
      workCentreId: json['work_centre_id'] as String,
      workCentreName: json['work_centre_name'] as String,
      actualMinutes: (json['actual_minutes'] as num?)?.toInt(),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      completedBy: json['completed_by'] as String?,
      completedByName: json['completed_by_name'] as String?,
      costRate: json['cost_rate'] as String?,
      startedAt: json['started_at'] == null
          ? null
          : DateTime.parse(json['started_at'] as String),
    );

Map<String, dynamic> _$ProductionOperationToJson(
  ProductionOperation instance,
) => <String, dynamic>{
  'actual_minutes': ?instance.actualMinutes,
  'completed_at': ?instance.completedAt?.toIso8601String(),
  'completed_by': ?instance.completedBy,
  'completed_by_name': ?instance.completedByName,
  'cost_rate': ?instance.costRate,
  'id': instance.id,
  'name': instance.name,
  'notes': instance.notes,
  'planned_end': instance.plannedEnd.toIso8601String(),
  'planned_minutes': instance.plannedMinutes,
  'planned_start': instance.plannedStart.toIso8601String(),
  'position': instance.position,
  'run_minutes_per_unit': instance.runMinutesPerUnit,
  'setup_minutes': instance.setupMinutes,
  'started_at': ?instance.startedAt?.toIso8601String(),
  'status': instance.status,
  'work_centre_code': instance.workCentreCode,
  'work_centre_id': instance.workCentreId,
  'work_centre_name': instance.workCentreName,
};
