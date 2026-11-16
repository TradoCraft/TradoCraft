// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pricing_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PricingPreview _$PricingPreviewFromJson(Map<String, dynamic> json) =>
    PricingPreview(
      customerDiscountPercent: json['customer_discount_percent'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((e) => QuotationLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      priceDate: DateTime.parse(json['price_date'] as String),
      priceZoneCode: json['price_zone_code'] as String,
      quoteDate: DateTime.parse(json['quote_date'] as String),
      subtotal: json['subtotal'] as String,
      suggestions: (json['suggestions'] as List<dynamic>)
          .map((e) => SalesSuggestion.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as String,
      unconfirmedLines: (json['unconfirmed_lines'] as num).toInt(),
      vatGroups: (json['vat_groups'] as List<dynamic>)
          .map((e) => VatGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
      vatTotal: json['vat_total'] as String,
      warnings: (json['warnings'] as List<dynamic>)
          .map((e) => SalesWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      buildingConstructionYear: (json['building_construction_year'] as num?)
          ?.toInt(),
      vatRegime: json['vat_regime'] as String?,
    );

Map<String, dynamic> _$PricingPreviewToJson(PricingPreview instance) =>
    <String, dynamic>{
      'building_construction_year': ?instance.buildingConstructionYear,
      'customer_discount_percent': instance.customerDiscountPercent,
      'lines': instance.lines,
      'price_date': instance.priceDate.toIso8601String(),
      'price_zone_code': instance.priceZoneCode,
      'quote_date': instance.quoteDate.toIso8601String(),
      'subtotal': instance.subtotal,
      'suggestions': instance.suggestions,
      'total': instance.total,
      'unconfirmed_lines': instance.unconfirmedLines,
      'vat_groups': instance.vatGroups,
      'vat_regime': ?instance.vatRegime,
      'vat_total': instance.vatTotal,
      'warnings': instance.warnings,
    };
