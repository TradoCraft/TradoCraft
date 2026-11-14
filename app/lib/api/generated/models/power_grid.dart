// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'power_grid.g.dart';

/// One grid of a country, e.g. 230 V single phase at 50 Hz.
@JsonSerializable()
class PowerGrid {
  const PowerGrid({
    required this.active,
    required this.countryCode,
    required this.frequencyHz,
    required this.id,
    required this.name,
    required this.phases,
    required this.voltageV,
  });
  
  factory PowerGrid.fromJson(Map<String, Object?> json) => _$PowerGridFromJson(json);
  
  final bool active;

  /// ISO 3166 alpha-2.
  @JsonKey(name: 'country_code')
  final String countryCode;

  /// 50 or 60
  @JsonKey(name: 'frequency_hz')
  final int frequencyHz;
  final String id;
  final String name;

  /// 1 or 3
  final int phases;

  /// Nominal voltage as quoted: phase-to-neutral for 1 phase, line-to-line for 3 phases.
  @JsonKey(name: 'voltage_v')
  final int voltageV;

  Map<String, Object?> toJson() => _$PowerGridToJson(this);
}
