// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_centre.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkCentre _$WorkCentreFromJson(Map<String, dynamic> json) => WorkCentre(
  active: json['active'] as bool,
  capacity: (json['capacity'] as num).toInt(),
  code: json['code'] as String,
  hours: (json['hours'] as List<dynamic>)
      .map((e) => WorkCentreHoursSlot.fromJson(e as Map<String, dynamic>))
      .toList(),
  id: json['id'] as String,
  name: json['name'] as String,
  notes: json['notes'] as String,
  openOperations: (json['open_operations'] as num).toInt(),
  sortOrder: (json['sort_order'] as num).toInt(),
  costPerHour: json['cost_per_hour'] as String?,
  divisionId: json['division_id'] as String?,
  divisionName: json['division_name'] as String?,
);

Map<String, dynamic> _$WorkCentreToJson(WorkCentre instance) =>
    <String, dynamic>{
      'active': instance.active,
      'capacity': instance.capacity,
      'code': instance.code,
      'cost_per_hour': ?instance.costPerHour,
      'division_id': ?instance.divisionId,
      'division_name': ?instance.divisionName,
      'hours': instance.hours,
      'id': instance.id,
      'name': instance.name,
      'notes': instance.notes,
      'open_operations': instance.openOperations,
      'sort_order': instance.sortOrder,
    };
