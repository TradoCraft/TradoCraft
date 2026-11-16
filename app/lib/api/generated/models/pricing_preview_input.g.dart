// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pricing_preview_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PricingPreviewInput _$PricingPreviewInputFromJson(Map<String, dynamic> json) =>
    PricingPreviewInput(
      customerId: json['customer_id'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((e) => QuotationLineInput.fromJson(e as Map<String, dynamic>))
          .toList(),
      buildingConstructionYear: (json['building_construction_year'] as num?)
          ?.toInt(),
      clearBuildingConstructionYear:
          json['clear_building_construction_year'] as bool?,
      deliveryCountryCode: json['delivery_country_code'] as String?,
      opportunityId: json['opportunity_id'] as String?,
      powerGridId: json['power_grid_id'] as String?,
      priceDate: json['price_date'] == null
          ? null
          : DateTime.parse(json['price_date'] as String),
      purpose: json['purpose'] as String?,
      quotationId: json['quotation_id'] as String?,
      quoteDate: json['quote_date'] == null
          ? null
          : DateTime.parse(json['quote_date'] as String),
      vatRegimeOverride: json['vat_regime_override'] as String?,
    );

Map<String, dynamic> _$PricingPreviewInputToJson(
  PricingPreviewInput instance,
) => <String, dynamic>{
  'building_construction_year': ?instance.buildingConstructionYear,
  'clear_building_construction_year': ?instance.clearBuildingConstructionYear,
  'customer_id': instance.customerId,
  'delivery_country_code': ?instance.deliveryCountryCode,
  'lines': instance.lines,
  'opportunity_id': ?instance.opportunityId,
  'power_grid_id': ?instance.powerGridId,
  'price_date': ?instance.priceDate?.toIso8601String(),
  'purpose': ?instance.purpose,
  'quotation_id': ?instance.quotationId,
  'quote_date': ?instance.quoteDate?.toIso8601String(),
  'vat_regime_override': ?instance.vatRegimeOverride,
};
