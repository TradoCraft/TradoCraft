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
    required this.nonDiscountable,
    required this.priceIsIndicative,
    required this.priceOnRequest,
    required this.productType,
    required this.tracking,
    required this.unit,
    required this.vatRate,
    this.barcode,
    this.defaultMediaId,
    this.defaultMediaKind,
    this.defaultProductionRemark,
    this.familyCode,
    this.familyId,
    this.heightMm,
    this.includedInTurnover,
    this.leadTimeDays,
    this.lengthMm,
    this.packagingCategoryCode,
    this.packagingCategoryId,
    this.reorderMax,
    this.reorderMin,
    this.standardCost,
    this.vatCategory,
    this.vatRateOverride,
    this.weightG,
    this.widthMm,
  });
  
  factory Product.fromJson(Map<String, Object?> json) => _$ProductFromJson(json);
  
  final bool active;
  @JsonKey(includeIfNull: false)
  final String? barcode;
  final String code;

  /// The default picture or video of the product (`GET /products/{id}/media/{id}`), if it has.
  /// media.
  @JsonKey(includeIfNull: false,name: 'default_media_id')
  final String? defaultMediaId;

  /// `image` or `video`: a video has no thumbnail to show in a list.
  @JsonKey(includeIfNull: false,name: 'default_media_kind')
  final String? defaultMediaKind;

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

  /// Whether this product contributes to turnover-based rebates. Null means unclassified.
  @JsonKey(includeIfNull: false,name: 'included_in_turnover')
  final bool? includedInTurnover;
  @JsonKey(includeIfNull: false,name: 'lead_time_days')
  final int? leadTimeDays;

  /// Outer dimensions of the packed product, in millimetres.
  @JsonKey(includeIfNull: false,name: 'length_mm')
  final int? lengthMm;
  final String name;

  /// Never discounted: no customer rebate and no manual line discount.
  @JsonKey(name: 'non_discountable')
  final bool nonDiscountable;
  @JsonKey(includeIfNull: false,name: 'packaging_category_code')
  final String? packagingCategoryCode;
  @JsonKey(includeIfNull: false,name: 'packaging_category_id')
  final String? packagingCategoryId;

  /// The list price applies but is printed as indicative.
  @JsonKey(name: 'price_is_indicative')
  final bool priceIsIndicative;

  /// No list price: the price is entered on each quotation line, which cannot be sent before.
  @JsonKey(name: 'price_on_request')
  final bool priceOnRequest;

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

  /// VAT category used to resolve country-specific default rates (`standard`, `intermediate`, `reduced`, `zero`).
  @JsonKey(includeIfNull: false,name: 'vat_category')
  final String? vatCategory;
  @JsonKey(name: 'vat_rate')
  final String vatRate;

  /// Optional explicit VAT rate overriding the country-category rate.
  @JsonKey(includeIfNull: false,name: 'vat_rate_override')
  final String? vatRateOverride;

  /// Packed weight in grams.
  @JsonKey(includeIfNull: false,name: 'weight_g')
  final int? weightG;
  @JsonKey(includeIfNull: false,name: 'width_mm')
  final int? widthMm;

  Map<String, Object?> toJson() => _$ProductToJson(this);
}
