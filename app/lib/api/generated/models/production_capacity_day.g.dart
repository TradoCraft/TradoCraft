// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_capacity_day.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionCapacityDay _$ProductionCapacityDayFromJson(
  Map<String, dynamic> json,
) => ProductionCapacityDay(
  availableMinutes: (json['available_minutes'] as num).toInt(),
  date: DateTime.parse(json['date'] as String),
  loadMinutes: (json['load_minutes'] as num).toInt(),
  overloaded: json['overloaded'] as bool,
);

Map<String, dynamic> _$ProductionCapacityDayToJson(
  ProductionCapacityDay instance,
) => <String, dynamic>{
  'available_minutes': instance.availableMinutes,
  'date': instance.date.toIso8601String(),
  'load_minutes': instance.loadMinutes,
  'overloaded': instance.overloaded,
};
