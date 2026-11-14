// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routing_operation_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoutingOperationInput _$RoutingOperationInputFromJson(
  Map<String, dynamic> json,
) => RoutingOperationInput(
  name: json['name'] as String,
  workCentreId: json['work_centre_id'] as String,
  notes: json['notes'] as String?,
  runMinutesPerUnit: json['run_minutes_per_unit'] as String?,
  setupMinutes: (json['setup_minutes'] as num?)?.toInt(),
);

Map<String, dynamic> _$RoutingOperationInputToJson(
  RoutingOperationInput instance,
) => <String, dynamic>{
  'name': instance.name,
  'notes': ?instance.notes,
  'run_minutes_per_unit': ?instance.runMinutesPerUnit,
  'setup_minutes': ?instance.setupMinutes,
  'work_centre_id': instance.workCentreId,
};
