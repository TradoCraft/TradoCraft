// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'power_supply.g.dart';

/// A way to power a product.
@JsonSerializable()
class PowerSupply {
  const PowerSupply({
    required this.currentType,
    required this.id,
    required this.tolerancePct,
    required this.voltageV,
    this.frequencyHz,
    this.phases,
  });
  
  factory PowerSupply.fromJson(Map<String, Object?> json) => _$PowerSupplyFromJson(json);
  
  /// ac | dc
  @JsonKey(name: 'current_type')
  final String currentType;

  /// 50 or 60; null means the product works on both (always null for DC).
  @JsonKey(includeIfNull: false,name: 'frequency_hz')
  final int? frequencyHz;
  final String id;

  /// 1 or 3 for AC; null for DC.
  @JsonKey(includeIfNull: false)
  final int? phases;

  /// Accepted deviation of the grid voltage from the nominal one, in percent.
  @JsonKey(name: 'tolerance_pct')
  final int tolerancePct;
  @JsonKey(name: 'voltage_v')
  final int voltageV;

  Map<String, Object?> toJson() => _$PowerSupplyToJson(this);
}
