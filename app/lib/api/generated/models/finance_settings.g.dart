// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FinanceSettings _$FinanceSettingsFromJson(Map<String, dynamic> json) =>
    FinanceSettings(
      priceTolerancePct: json['price_tolerance_pct'] as String,
      quantityTolerancePct: json['quantity_tolerance_pct'] as String,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$FinanceSettingsToJson(FinanceSettings instance) =>
    <String, dynamic>{
      'price_tolerance_pct': instance.priceTolerancePct,
      'quantity_tolerance_pct': instance.quantityTolerancePct,
      'updated_at': ?instance.updatedAt?.toIso8601String(),
    };
