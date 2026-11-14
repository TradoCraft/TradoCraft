// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'power_grid.dart';
import 'power_status.dart';
import 'power_supply.dart';

part 'power_compatibility_report.g.dart';

@JsonSerializable()
class PowerCompatibilityReport {
  const PowerCompatibilityReport({
    required this.available,
    required this.countryCode,
    required this.status,
    required this.supported,
  });
  
  factory PowerCompatibilityReport.fromJson(Map<String, Object?> json) => _$PowerCompatibilityReportFromJson(json);
  
  /// The grids the product was checked against.
  final List<PowerGrid> available;
  @JsonKey(name: 'country_code')
  final String countryCode;
  final PowerStatus status;

  /// The supply profiles of the product (AC only when the status is incompatible).
  final List<PowerSupply> supported;

  Map<String, Object?> toJson() => _$PowerCompatibilityReportToJson(this);
}
