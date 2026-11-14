// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'power_supply.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PowerSupply _$PowerSupplyFromJson(Map<String, dynamic> json) => PowerSupply(
  currentType: json['current_type'] as String,
  id: json['id'] as String,
  tolerancePct: (json['tolerance_pct'] as num).toInt(),
  voltageV: (json['voltage_v'] as num).toInt(),
  frequencyHz: (json['frequency_hz'] as num?)?.toInt(),
  phases: (json['phases'] as num?)?.toInt(),
  voltageMaxV: (json['voltage_max_v'] as num?)?.toInt(),
  voltageMinV: (json['voltage_min_v'] as num?)?.toInt(),
);

Map<String, dynamic> _$PowerSupplyToJson(PowerSupply instance) =>
    <String, dynamic>{
      'current_type': instance.currentType,
      'frequency_hz': ?instance.frequencyHz,
      'id': instance.id,
      'phases': ?instance.phases,
      'tolerance_pct': instance.tolerancePct,
      'voltage_max_v': ?instance.voltageMaxV,
      'voltage_min_v': ?instance.voltageMinV,
      'voltage_v': instance.voltageV,
    };
