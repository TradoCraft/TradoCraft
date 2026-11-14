// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'power_supply_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PowerSupplyInput _$PowerSupplyInputFromJson(Map<String, dynamic> json) =>
    PowerSupplyInput(
      currentType: json['current_type'] as String,
      voltageV: (json['voltage_v'] as num).toInt(),
      frequencyHz: (json['frequency_hz'] as num?)?.toInt(),
      phases: (json['phases'] as num?)?.toInt(),
      tolerancePct: (json['tolerance_pct'] as num?)?.toInt(),
      voltageMaxV: (json['voltage_max_v'] as num?)?.toInt(),
      voltageMinV: (json['voltage_min_v'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PowerSupplyInputToJson(PowerSupplyInput instance) =>
    <String, dynamic>{
      'current_type': instance.currentType,
      'frequency_hz': ?instance.frequencyHz,
      'phases': ?instance.phases,
      'tolerance_pct': ?instance.tolerancePct,
      'voltage_max_v': ?instance.voltageMaxV,
      'voltage_min_v': ?instance.voltageMinV,
      'voltage_v': instance.voltageV,
    };
