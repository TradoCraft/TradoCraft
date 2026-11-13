// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'incoming_supply.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IncomingSupply _$IncomingSupplyFromJson(Map<String, dynamic> json) =>
    IncomingSupply(
      lines: (json['lines'] as List<dynamic>)
          .map((e) => IncomingLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      openQuantity: json['open_quantity'] as String,
      productId: json['product_id'] as String,
      nextExpectedDate: json['next_expected_date'] == null
          ? null
          : DateTime.parse(json['next_expected_date'] as String),
    );

Map<String, dynamic> _$IncomingSupplyToJson(IncomingSupply instance) =>
    <String, dynamic>{
      'lines': instance.lines,
      'next_expected_date': ?instance.nextExpectedDate?.toIso8601String(),
      'open_quantity': instance.openQuantity,
      'product_id': instance.productId,
    };
