// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_capacity_centre.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionCapacityCentre _$ProductionCapacityCentreFromJson(
  Map<String, dynamic> json,
) => ProductionCapacityCentre(
  active: json['active'] as bool,
  capacity: (json['capacity'] as num).toInt(),
  code: json['code'] as String,
  days: (json['days'] as List<dynamic>)
      .map((e) => ProductionCapacityDay.fromJson(e as Map<String, dynamic>))
      .toList(),
  id: json['id'] as String,
  name: json['name'] as String,
  totalAvailableMinutes: (json['total_available_minutes'] as num).toInt(),
  totalLoadMinutes: (json['total_load_minutes'] as num).toInt(),
  divisionId: json['division_id'] as String?,
);

Map<String, dynamic> _$ProductionCapacityCentreToJson(
  ProductionCapacityCentre instance,
) => <String, dynamic>{
  'active': instance.active,
  'capacity': instance.capacity,
  'code': instance.code,
  'days': instance.days,
  'division_id': ?instance.divisionId,
  'id': instance.id,
  'name': instance.name,
  'total_available_minutes': instance.totalAvailableMinutes,
  'total_load_minutes': instance.totalLoadMinutes,
};
