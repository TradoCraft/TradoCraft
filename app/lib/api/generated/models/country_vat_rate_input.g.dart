// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'country_vat_rate_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CountryVatRateInput _$CountryVatRateInputFromJson(Map<String, dynamic> json) =>
    CountryVatRateInput(
      category: json['category'] as String,
      countryCode: json['country_code'] as String,
      rate: json['rate'] as String,
      closePrevious: json['close_previous'] as bool?,
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
      minBuildingAgeYears: (json['min_building_age_years'] as num?)?.toInt(),
      notes: json['notes'] as String?,
      startDate: json['start_date'] == null
          ? null
          : DateTime.parse(json['start_date'] as String),
    );

Map<String, dynamic> _$CountryVatRateInputToJson(
  CountryVatRateInput instance,
) => <String, dynamic>{
  'category': instance.category,
  'close_previous': ?instance.closePrevious,
  'country_code': instance.countryCode,
  'end_date': ?instance.endDate?.toIso8601String(),
  'min_building_age_years': ?instance.minBuildingAgeYears,
  'notes': ?instance.notes,
  'rate': instance.rate,
  'start_date': ?instance.startDate?.toIso8601String(),
};
