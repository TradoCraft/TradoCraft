// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quotation_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

QuotationInput _$QuotationInputFromJson(Map<String, dynamic> json) =>
    QuotationInput(
      customerId: json['customer_id'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((e) => QuotationLineInput.fromJson(e as Map<String, dynamic>))
          .toList(),
      buildingConstructionYear: (json['building_construction_year'] as num?)
          ?.toInt(),
      clearBuildingConstructionYear:
          json['clear_building_construction_year'] as bool?,
      clearPowerGrid: json['clear_power_grid'] as bool?,
      clearVatRegimeOverride: json['clear_vat_regime_override'] as bool?,
      deliveryCountryCode: json['delivery_country_code'] as String?,
      expectedVersion: (json['expected_version'] as num?)?.toInt(),
      notes: json['notes'] as String?,
      opportunityId: json['opportunity_id'] as String?,
      powerGridId: json['power_grid_id'] as String?,
      priceDate: json['price_date'] == null
          ? null
          : DateTime.parse(json['price_date'] as String),
      purpose: json['purpose'] as String?,
      quoteDate: json['quote_date'] == null
          ? null
          : DateTime.parse(json['quote_date'] as String),
      validDays: (json['valid_days'] as num?)?.toInt(),
      vatRegimeOverride: json['vat_regime_override'] as String?,
    );

Map<String, dynamic> _$QuotationInputToJson(
  QuotationInput instance,
) => <String, dynamic>{
  'building_construction_year': ?instance.buildingConstructionYear,
  'clear_building_construction_year': ?instance.clearBuildingConstructionYear,
  'clear_power_grid': ?instance.clearPowerGrid,
  'clear_vat_regime_override': ?instance.clearVatRegimeOverride,
  'customer_id': instance.customerId,
  'delivery_country_code': ?instance.deliveryCountryCode,
  'expected_version': ?instance.expectedVersion,
  'lines': instance.lines,
  'notes': ?instance.notes,
  'opportunity_id': ?instance.opportunityId,
  'power_grid_id': ?instance.powerGridId,
  'price_date': ?instance.priceDate?.toIso8601String(),
  'purpose': ?instance.purpose,
  'quote_date': ?instance.quoteDate?.toIso8601String(),
  'valid_days': ?instance.validDays,
  'vat_regime_override': ?instance.vatRegimeOverride,
};
