// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routing_operation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoutingOperation _$RoutingOperationFromJson(Map<String, dynamic> json) =>
    RoutingOperation(
      id: json['id'] as String,
      name: json['name'] as String,
      notes: json['notes'] as String,
      position: (json['position'] as num).toInt(),
      runMinutesPerUnit: json['run_minutes_per_unit'] as String,
      setupMinutes: (json['setup_minutes'] as num).toInt(),
      workCentreCode: json['work_centre_code'] as String,
      workCentreId: json['work_centre_id'] as String,
      workCentreName: json['work_centre_name'] as String,
    );

Map<String, dynamic> _$RoutingOperationToJson(RoutingOperation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'notes': instance.notes,
      'position': instance.position,
      'run_minutes_per_unit': instance.runMinutesPerUnit,
      'setup_minutes': instance.setupMinutes,
      'work_centre_code': instance.workCentreCode,
      'work_centre_id': instance.workCentreId,
      'work_centre_name': instance.workCentreName,
    };
