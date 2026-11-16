// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'country_vat_rate.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CountryVatRate _$CountryVatRateFromJson(Map<String, dynamic> json) =>
    CountryVatRate(
      category: json['category'] as String,
      countryCode: json['country_code'] as String,
      id: json['id'] as String,
      notes: json['notes'] as String,
      rate: json['rate'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
      minBuildingAgeYears: (json['min_building_age_years'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CountryVatRateToJson(CountryVatRate instance) =>
    <String, dynamic>{
      'category': instance.category,
      'country_code': instance.countryCode,
      'end_date': ?instance.endDate?.toIso8601String(),
      'id': instance.id,
      'min_building_age_years': ?instance.minBuildingAgeYears,
      'notes': instance.notes,
      'rate': instance.rate,
      'start_date': instance.startDate.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
