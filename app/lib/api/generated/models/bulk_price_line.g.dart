// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bulk_price_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BulkPriceLine _$BulkPriceLineFromJson(Map<String, dynamic> json) =>
    BulkPriceLine(
      conflict: json['conflict'] as bool,
      currentPrice: json['current_price'] as String,
      currentValidFrom: DateTime.parse(json['current_valid_from'] as String),
      newPrice: json['new_price'] as String,
      productCode: json['product_code'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      zoneCode: json['zone_code'] as String,
      zoneId: json['zone_id'] as String,
      replacedPrice: json['replaced_price'] as String?,
    );

Map<String, dynamic> _$BulkPriceLineToJson(BulkPriceLine instance) =>
    <String, dynamic>{
      'conflict': instance.conflict,
      'current_price': instance.currentPrice,
      'current_valid_from': instance.currentValidFrom.toIso8601String(),
      'new_price': instance.newPrice,
      'product_code': instance.productCode,
      'product_id': instance.productId,
      'product_name': instance.productName,
      'replaced_price': ?instance.replacedPrice,
      'zone_code': instance.zoneCode,
      'zone_id': instance.zoneId,
    };
