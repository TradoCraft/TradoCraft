// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_zone_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceZoneInput _$PriceZoneInputFromJson(Map<String, dynamic> json) =>
    PriceZoneInput(
      code: json['code'] as String,
      name: json['name'] as String,
      defaultMultiplier: json['default_multiplier'] as String?,
      defaultRounding: json['default_rounding'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PriceZoneInputToJson(PriceZoneInput instance) =>
    <String, dynamic>{
      'code': instance.code,
      'default_multiplier': ?instance.defaultMultiplier,
      'default_rounding': ?instance.defaultRounding,
      'name': instance.name,
      'sort_order': ?instance.sortOrder,
    };
