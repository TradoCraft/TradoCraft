// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_centre_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkCentreInput _$WorkCentreInputFromJson(Map<String, dynamic> json) =>
    WorkCentreInput(
      code: json['code'] as String,
      name: json['name'] as String,
      active: json['active'] as bool?,
      capacity: (json['capacity'] as num?)?.toInt(),
      costPerHour: json['cost_per_hour'] as String?,
      divisionId: json['division_id'] as String?,
      notes: json['notes'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt(),
    );

Map<String, dynamic> _$WorkCentreInputToJson(WorkCentreInput instance) =>
    <String, dynamic>{
      'active': ?instance.active,
      'capacity': ?instance.capacity,
      'code': instance.code,
      'cost_per_hour': ?instance.costPerHour,
      'division_id': ?instance.divisionId,
      'name': instance.name,
      'notes': ?instance.notes,
      'sort_order': ?instance.sortOrder,
    };
