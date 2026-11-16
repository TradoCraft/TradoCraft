// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'configured_quotation_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConfiguredQuotationInput _$ConfiguredQuotationInputFromJson(
  Map<String, dynamic> json,
) => ConfiguredQuotationInput(
  customerId: json['customer_id'] as String,
  externalRef: json['external_ref'] as String,
  lines: (json['lines'] as List<dynamic>)
      .map((e) => ConfiguredLineInput.fromJson(e as Map<String, dynamic>))
      .toList(),
  source: json['source'] as String,
  buildingConstructionYear: (json['building_construction_year'] as num?)
      ?.toInt(),
  configuration: json['configuration'],
  deliveryCountryCode: json['delivery_country_code'] as String?,
  notes: json['notes'] as String?,
  powerGridId: json['power_grid_id'] as String?,
  priceZoneCode: json['price_zone_code'] as String?,
  purpose: json['purpose'] as String?,
  strict: json['strict'] as bool?,
  validDays: (json['valid_days'] as num?)?.toInt(),
  vatRegimeOverride: json['vat_regime_override'] as String?,
);

Map<String, dynamic> _$ConfiguredQuotationInputToJson(
  ConfiguredQuotationInput instance,
) => <String, dynamic>{
  'building_construction_year': ?instance.buildingConstructionYear,
  'configuration': ?instance.configuration,
  'customer_id': instance.customerId,
  'delivery_country_code': ?instance.deliveryCountryCode,
  'external_ref': instance.externalRef,
  'lines': instance.lines,
  'notes': ?instance.notes,
  'power_grid_id': ?instance.powerGridId,
  'price_zone_code': ?instance.priceZoneCode,
  'purpose': ?instance.purpose,
  'source': instance.source,
  'strict': ?instance.strict,
  'valid_days': ?instance.validDays,
  'vat_regime_override': ?instance.vatRegimeOverride,
};
