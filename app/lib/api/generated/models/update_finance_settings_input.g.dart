// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_finance_settings_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateFinanceSettingsInput _$UpdateFinanceSettingsInputFromJson(
  Map<String, dynamic> json,
) => UpdateFinanceSettingsInput(
  priceTolerancePct: json['price_tolerance_pct'] as String?,
  quantityTolerancePct: json['quantity_tolerance_pct'] as String?,
);

Map<String, dynamic> _$UpdateFinanceSettingsInputToJson(
  UpdateFinanceSettingsInput instance,
) => <String, dynamic>{
  'price_tolerance_pct': ?instance.priceTolerancePct,
  'quantity_tolerance_pct': ?instance.quantityTolerancePct,
};
