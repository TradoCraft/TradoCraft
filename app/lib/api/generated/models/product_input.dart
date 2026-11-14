// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_input.g.dart';

@JsonSerializable()
class ProductInput {
  const ProductInput({
    required this.code,
    required this.name,
    required this.vatRate,
    this.active,
    this.barcode,
    this.defaultProductionRemark,
    this.description,
    this.familyId,
    this.heightMm,
    this.leadTimeDays,
    this.lengthMm,
    this.packagingCategoryId,
    this.pricingType,
    this.productType,
    this.reorderMax,
    this.reorderMin,
    this.standardCost,
    this.tracking,
    this.unit,
    this.weightG,
    this.widthMm,
  });
  
  factory ProductInput.fromJson(Map<String, Object?> json) => _$ProductInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false)
  final String? barcode;
  final String code;

  /// Internal remark that new quotation lines of this product start with (never printed for.
  /// customers).
  @JsonKey(includeIfNull: false,name: 'default_production_remark')
  final String? defaultProductionRemark;
  @JsonKey(includeIfNull: false)
  final String? description;
  @JsonKey(includeIfNull: false,name: 'family_id')
  final String? familyId;
  @JsonKey(includeIfNull: false,name: 'height_mm')
  final int? heightMm;
  @JsonKey(includeIfNull: false,name: 'lead_time_days')
  final int? leadTimeDays;

  /// Dimensions (mm) and weight (g) of the packed product; each must be positive when given.
  @JsonKey(includeIfNull: false,name: 'length_mm')
  final int? lengthMm;
  final String name;

  /// Must be an active packaging category.
  @JsonKey(includeIfNull: false,name: 'packaging_category_id')
  final String? packagingCategoryId;

  /// list | net | indicative
  @JsonKey(includeIfNull: false,name: 'pricing_type')
  final String? pricingType;
  @JsonKey(includeIfNull: false,name: 'product_type')
  final String? productType;
  @JsonKey(includeIfNull: false,name: 'reorder_max')
  final String? reorderMax;
  @JsonKey(includeIfNull: false,name: 'reorder_min')
  final String? reorderMin;

  /// Ignored (the stored cost is kept) without the permission `inventory.cost`.
  @JsonKey(includeIfNull: false,name: 'standard_cost')
  final String? standardCost;

  /// none | serial | lot. Services are not tracked.
  @JsonKey(includeIfNull: false)
  final String? tracking;
  @JsonKey(includeIfNull: false)
  final String? unit;
  @JsonKey(name: 'vat_rate')
  final String vatRate;
  @JsonKey(includeIfNull: false,name: 'weight_g')
  final int? weightG;
  @JsonKey(includeIfNull: false,name: 'width_mm')
  final int? widthMm;

  Map<String, Object?> toJson() => _$ProductInputToJson(this);
}
