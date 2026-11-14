// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product.g.dart';

@JsonSerializable()
class Product {
  const Product({
    required this.active,
    required this.code,
    required this.description,
    required this.id,
    required this.name,
    required this.pricingType,
    required this.productType,
    required this.tracking,
    required this.unit,
    required this.vatRate,
    this.barcode,
    this.defaultProductionRemark,
    this.familyCode,
    this.familyId,
    this.heightMm,
    this.leadTimeDays,
    this.lengthMm,
    this.packagingCategoryCode,
    this.packagingCategoryId,
    this.reorderMax,
    this.reorderMin,
    this.standardCost,
    this.weightG,
    this.widthMm,
  });
  
  factory Product.fromJson(Map<String, Object?> json) => _$ProductFromJson(json);
  
  final bool active;
  @JsonKey(includeIfNull: false)
  final String? barcode;
  final String code;

  /// Internal remark that new quotation lines of this product start with.
  @JsonKey(includeIfNull: false,name: 'default_production_remark')
  final String? defaultProductionRemark;
  final String description;
  @JsonKey(includeIfNull: false,name: 'family_code')
  final String? familyCode;
  @JsonKey(includeIfNull: false,name: 'family_id')
  final String? familyId;
  @JsonKey(includeIfNull: false,name: 'height_mm')
  final int? heightMm;
  final String id;
  @JsonKey(includeIfNull: false,name: 'lead_time_days')
  final int? leadTimeDays;

  /// Outer dimensions of the packed product, in millimetres.
  @JsonKey(includeIfNull: false,name: 'length_mm')
  final int? lengthMm;
  final String name;
  @JsonKey(includeIfNull: false,name: 'packaging_category_code')
  final String? packagingCategoryCode;
  @JsonKey(includeIfNull: false,name: 'packaging_category_id')
  final String? packagingCategoryId;

  /// list (rebates apply) | net (fixed net price, never discounted) |.
  /// indicative (price must be confirmed on each quotation).
  @JsonKey(name: 'pricing_type')
  final String pricingType;

  /// purchased | manufactured | configurable | service
  @JsonKey(name: 'product_type')
  final String productType;

  /// Order up to this quantity.
  @JsonKey(includeIfNull: false,name: 'reorder_max')
  final String? reorderMax;

  /// Reorder when the available stock falls below this quantity.
  @JsonKey(includeIfNull: false,name: 'reorder_min')
  final String? reorderMin;

  /// Standard cost per stock unit. Only returned with the permission `inventory.cost`, else null.
  @JsonKey(includeIfNull: false,name: 'standard_cost')
  final String? standardCost;

  /// none | serial | lot — serial-tracked products get an individual serial number per unit,.
  /// lot-tracked products are stocked per lot or batch.
  final String tracking;
  final String unit;
  @JsonKey(name: 'vat_rate')
  final String vatRate;

  /// Packed weight in grams.
  @JsonKey(includeIfNull: false,name: 'weight_g')
  final int? weightG;
  @JsonKey(includeIfNull: false,name: 'width_mm')
  final int? widthMm;

  Map<String, Object?> toJson() => _$ProductToJson(this);
}
