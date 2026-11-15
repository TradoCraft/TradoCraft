// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_zone_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListZoneInput _$PriceListZoneInputFromJson(Map<String, dynamic> json) =>
    PriceListZoneInput(
      languages: (json['languages'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      priceZoneId: json['price_zone_id'] as String,
    );

Map<String, dynamic> _$PriceListZoneInputToJson(PriceListZoneInput instance) =>
    <String, dynamic>{
      'languages': instance.languages,
      'price_zone_id': instance.priceZoneId,
    };
