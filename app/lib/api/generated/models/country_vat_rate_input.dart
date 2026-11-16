// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'country_vat_rate_input.g.dart';

/// Request payload for creating or updating a country VAT rate rule.
@JsonSerializable()
class CountryVatRateInput {
  const CountryVatRateInput({
    required this.category,
    required this.countryCode,
    required this.rate,
    this.closePrevious,
    this.endDate,
    this.minBuildingAgeYears,
    this.notes,
    this.startDate,
  });
  
  factory CountryVatRateInput.fromJson(Map<String, Object?> json) => _$CountryVatRateInputFromJson(json);
  
  final String category;

  /// When creating a new rate period, set `end_date = start_date - 1` on any.
  /// earlier rule for the same `(country_code, category, min_building_age_years)`.
  /// that would otherwise remain open past the new start date.
  @JsonKey(includeIfNull: false,name: 'close_previous')
  final bool? closePrevious;
  @JsonKey(name: 'country_code')
  final String countryCode;
  @JsonKey(includeIfNull: false,name: 'end_date')
  final DateTime? endDate;
  @JsonKey(includeIfNull: false,name: 'min_building_age_years')
  final int? minBuildingAgeYears;
  @JsonKey(includeIfNull: false)
  final String? notes;
  final String rate;
  @JsonKey(includeIfNull: false,name: 'start_date')
  final DateTime? startDate;

  Map<String, Object?> toJson() => _$CountryVatRateInputToJson(this);
}
