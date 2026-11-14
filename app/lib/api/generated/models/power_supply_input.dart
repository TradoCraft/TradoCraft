// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'power_supply_input.g.dart';

@JsonSerializable()
class PowerSupplyInput {
  const PowerSupplyInput({
    required this.currentType,
    required this.voltageV,
    this.frequencyHz,
    this.phases,
    this.tolerancePct,
  });
  
  factory PowerSupplyInput.fromJson(Map<String, Object?> json) => _$PowerSupplyInputFromJson(json);
  
  @JsonKey(name: 'current_type')
  final String currentType;
  @JsonKey(includeIfNull: false,name: 'frequency_hz')
  final int? frequencyHz;
  @JsonKey(includeIfNull: false)
  final int? phases;

  /// Defaults to 10.
  @JsonKey(includeIfNull: false,name: 'tolerance_pct')
  final int? tolerancePct;
  @JsonKey(name: 'voltage_v')
  final int voltageV;

  Map<String, Object?> toJson() => _$PowerSupplyInputToJson(this);
}
