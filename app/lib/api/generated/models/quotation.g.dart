// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quotation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Quotation _$QuotationFromJson(Map<String, dynamic> json) => Quotation(
  updatedAt: DateTime.parse(json['updated_at'] as String),
  companyId: json['company_id'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  createdBy: json['created_by'] as String,
  currency: json['currency'] as String,
  customerCity: json['customer_city'] as String,
  customerCountryCode: json['customer_country_code'] as String,
  customerDiscountPercent: json['customer_discount_percent'] as String,
  customerId: json['customer_id'] as String,
  customerLanguage: json['customer_language'] as String,
  customerName: json['customer_name'] as String,
  customerPostalCode: json['customer_postal_code'] as String,
  customerStreet: json['customer_street'] as String,
  id: json['id'] as String,
  lines: (json['lines'] as List<dynamic>)
      .map((e) => QuotationLine.fromJson(e as Map<String, dynamic>))
      .toList(),
  notes: json['notes'] as String,
  number: json['number'] as String,
  revision: (json['revision'] as num).toInt(),
  priceDate: DateTime.parse(json['price_date'] as String),
  priceZoneCode: json['price_zone_code'] as String,
  purpose: json['purpose'] as String,
  quoteDate: DateTime.parse(json['quote_date'] as String),
  warnings: (json['warnings'] as List<dynamic>)
      .map((e) => SalesWarning.fromJson(e as Map<String, dynamic>))
      .toList(),
  shippingStatus: json['shipping_status'] as String,
  status: QuotationStatus.fromJson(json['status'] as String),
  subtotal: json['subtotal'] as String,
  suggestions: (json['suggestions'] as List<dynamic>)
      .map((e) => SalesSuggestion.fromJson(e as Map<String, dynamic>))
      .toList(),
  vatGroups: (json['vat_groups'] as List<dynamic>)
      .map((e) => VatGroup.fromJson(e as Map<String, dynamic>))
      .toList(),
  vatRegime: json['vat_regime'] as String,
  vatTotal: json['vat_total'] as String,
  validUntil: DateTime.parse(json['valid_until'] as String),
  total: json['total'] as String,
  supersedesId: json['supersedes_id'] as String?,
  customerVatNumber: json['customer_vat_number'] as String?,
  sentAt: json['sent_at'] == null
      ? null
      : DateTime.parse(json['sent_at'] as String),
  powerGridId: json['power_grid_id'] as String?,
  deliveryCountryCode: json['delivery_country_code'] as String?,
  vatRegimeOverride: json['vat_regime_override'] as String?,
  buildingConstructionYear: (json['building_construction_year'] as num?)
      ?.toInt(),
  opportunityId: json['opportunity_id'] as String?,
);

Map<String, dynamic> _$QuotationToJson(Quotation instance) => <String, dynamic>{
  'building_construction_year': ?instance.buildingConstructionYear,
  'company_id': instance.companyId,
  'created_at': instance.createdAt.toIso8601String(),
  'created_by': instance.createdBy,
  'currency': instance.currency,
  'customer_city': instance.customerCity,
  'customer_country_code': instance.customerCountryCode,
  'customer_discount_percent': instance.customerDiscountPercent,
  'customer_id': instance.customerId,
  'customer_language': instance.customerLanguage,
  'customer_name': instance.customerName,
  'customer_postal_code': instance.customerPostalCode,
  'customer_street': instance.customerStreet,
  'customer_vat_number': ?instance.customerVatNumber,
  'delivery_country_code': ?instance.deliveryCountryCode,
  'id': instance.id,
  'lines': instance.lines,
  'notes': instance.notes,
  'number': instance.number,
  'opportunity_id': ?instance.opportunityId,
  'power_grid_id': ?instance.powerGridId,
  'price_date': instance.priceDate.toIso8601String(),
  'price_zone_code': instance.priceZoneCode,
  'purpose': instance.purpose,
  'quote_date': instance.quoteDate.toIso8601String(),
  'revision': instance.revision,
  'sent_at': ?instance.sentAt?.toIso8601String(),
  'shipping_status': instance.shippingStatus,
  'status': instance.status,
  'subtotal': instance.subtotal,
  'suggestions': instance.suggestions,
  'supersedes_id': ?instance.supersedesId,
  'total': instance.total,
  'updated_at': instance.updatedAt.toIso8601String(),
  'valid_until': instance.validUntil.toIso8601String(),
  'vat_groups': instance.vatGroups,
  'vat_regime': instance.vatRegime,
  'vat_regime_override': ?instance.vatRegimeOverride,
  'vat_total': instance.vatTotal,
  'warnings': instance.warnings,
};
