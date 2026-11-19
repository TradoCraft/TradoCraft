// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductInput _$ProductInputFromJson(Map<String, dynamic> json) => ProductInput(
  code: json['code'] as String,
  name: json['name'] as String,
  active: json['active'] as bool?,
  barcode: json['barcode'] as String?,
  defaultProductionRemark: json['default_production_remark'] as String?,
  description: json['description'] as String?,
  familyId: json['family_id'] as String?,
  heightMm: (json['height_mm'] as num?)?.toInt(),
  leadTimeDays: (json['lead_time_days'] as num?)?.toInt(),
  lengthMm: (json['length_mm'] as num?)?.toInt(),
  nonDiscountable: json['non_discountable'] as bool?,
  packagingCategoryId: json['packaging_category_id'] as String?,
  priceIsIndicative: json['price_is_indicative'] as bool?,
  priceOnRequest: json['price_on_request'] as bool?,
  productType: json['product_type'] as String?,
  reorderMax: json['reorder_max'] as String?,
  reorderMin: json['reorder_min'] as String?,
  standardCost: json['standard_cost'] as String?,
  tracking: json['tracking'] as String?,
  unit: json['unit'] as String?,
  vatCategory: json['vat_category'] as String?,
  vatRate: json['vat_rate'] as String?,
  vatRateOverride: json['vat_rate_override'] as String?,
  weightG: (json['weight_g'] as num?)?.toInt(),
  widthMm: (json['width_mm'] as num?)?.toInt(),
);

Map<String, dynamic> _$ProductInputToJson(ProductInput instance) =>
    <String, dynamic>{
      'active': ?instance.active,
      'barcode': ?instance.barcode,
      'code': instance.code,
      'default_production_remark': ?instance.defaultProductionRemark,
      'description': ?instance.description,
      'family_id': ?instance.familyId,
      'height_mm': ?instance.heightMm,
      'lead_time_days': ?instance.leadTimeDays,
      'length_mm': ?instance.lengthMm,
      'name': instance.name,
      'non_discountable': ?instance.nonDiscountable,
      'packaging_category_id': ?instance.packagingCategoryId,
      'price_is_indicative': ?instance.priceIsIndicative,
      'price_on_request': ?instance.priceOnRequest,
      'product_type': ?instance.productType,
      'reorder_max': ?instance.reorderMax,
      'reorder_min': ?instance.reorderMin,
      'standard_cost': ?instance.standardCost,
      'tracking': ?instance.tracking,
      'unit': ?instance.unit,
      'vat_category': ?instance.vatCategory,
      'vat_rate': ?instance.vatRate,
      'vat_rate_override': ?instance.vatRateOverride,
      'weight_g': ?instance.weightG,
      'width_mm': ?instance.widthMm,
    };
