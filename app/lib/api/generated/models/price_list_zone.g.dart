// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_zone.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListZone _$PriceListZoneFromJson(Map<String, dynamic> json) =>
    PriceListZone(
      languages: (json['languages'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      priceZoneCode: json['price_zone_code'] as String,
      priceZoneId: json['price_zone_id'] as String,
      priceZoneName: json['price_zone_name'] as String,
      sortOrder: (json['sort_order'] as num).toInt(),
    );

Map<String, dynamic> _$PriceListZoneToJson(PriceListZone instance) =>
    <String, dynamic>{
      'languages': instance.languages,
      'price_zone_code': instance.priceZoneCode,
      'price_zone_id': instance.priceZoneId,
      'price_zone_name': instance.priceZoneName,
      'sort_order': instance.sortOrder,
    };
