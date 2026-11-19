// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'zone_price_correction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ZonePriceCorrection _$ZonePriceCorrectionFromJson(Map<String, dynamic> json) =>
    ZonePriceCorrection(
      unitPrice: json['unit_price'] as String,
      validFrom: DateTime.parse(json['valid_from'] as String),
    );

Map<String, dynamic> _$ZonePriceCorrectionToJson(
  ZonePriceCorrection instance,
) => <String, dynamic>{
  'unit_price': instance.unitPrice,
  'valid_from': instance.validFrom.toIso8601String(),
};
