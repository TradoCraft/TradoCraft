// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'power_grid_input.g.dart';

@JsonSerializable()
class PowerGridInput {
  const PowerGridInput({
    required this.countryCode,
    required this.frequencyHz,
    required this.phases,
    required this.voltageV,
    this.active,
    this.name,
  });
  
  factory PowerGridInput.fromJson(Map<String, Object?> json) => _$PowerGridInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(name: 'country_code')
  final String countryCode;
  @JsonKey(name: 'frequency_hz')
  final int frequencyHz;

  /// Generated from the other fields when empty.
  @JsonKey(includeIfNull: false)
  final String? name;
  final int phases;
  @JsonKey(name: 'voltage_v')
  final int voltageV;

  Map<String, Object?> toJson() => _$PowerGridInputToJson(this);
}
