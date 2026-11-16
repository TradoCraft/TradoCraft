// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'country_vat_rate.g.dart';

/// A country VAT rate rule with an effective date range and optional building-age threshold.
@JsonSerializable()
class CountryVatRate {
  const CountryVatRate({
    required this.category,
    required this.countryCode,
    required this.id,
    required this.notes,
    required this.rate,
    required this.startDate,
    required this.updatedAt,
    this.endDate,
    this.minBuildingAgeYears,
  });
  
  factory CountryVatRate.fromJson(Map<String, Object?> json) => _$CountryVatRateFromJson(json);
  
  final String category;
  @JsonKey(name: 'country_code')
  final String countryCode;
  @JsonKey(includeIfNull: false,name: 'end_date')
  final DateTime? endDate;
  final String id;
  @JsonKey(includeIfNull: false,name: 'min_building_age_years')
  final int? minBuildingAgeYears;
  final String notes;
  final String rate;
  @JsonKey(name: 'start_date')
  final DateTime startDate;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$CountryVatRateToJson(this);
}
