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
    this.active,
    this.barcode,
    this.defaultProductionRemark,
    this.description,
    this.familyId,
    this.heightMm,
    this.includedInTurnover,
    this.leadTimeDays,
    this.lengthMm,
    this.nonDiscountable,
    this.packagingCategoryId,
    this.priceIsIndicative,
    this.priceOnRequest,
    this.productType,
    this.reorderMax,
    this.reorderMin,
    this.standardCost,
    this.tracking,
    this.unit,
    this.vatCategory,
    this.vatRate,
    this.vatRateOverride,
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

  /// Whether this product contributes to turnover-based rebates. On update, omission preserves.
  /// the stored classification and null clears it.
  @JsonKey(includeIfNull: false,name: 'included_in_turnover')
  final bool? includedInTurnover;
  @JsonKey(includeIfNull: false,name: 'lead_time_days')
  final int? leadTimeDays;

  /// Dimensions (mm) and weight (g) of the packed product; each must be positive when given.
  @JsonKey(includeIfNull: false,name: 'length_mm')
  final int? lengthMm;
  final String name;

  /// Never discounted: no customer rebate and no manual line discount.
  @JsonKey(includeIfNull: false,name: 'non_discountable')
  final bool? nonDiscountable;

  /// Must be an active packaging category.
  @JsonKey(includeIfNull: false,name: 'packaging_category_id')
  final String? packagingCategoryId;

  /// The list price applies but is printed as indicative.
  @JsonKey(includeIfNull: false,name: 'price_is_indicative')
  final bool? priceIsIndicative;

  /// No list price: the price is entered on each quotation line, which cannot be sent before.
  @JsonKey(includeIfNull: false,name: 'price_on_request')
  final bool? priceOnRequest;
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

  /// `standard` (default), `intermediate`, `reduced`, or `zero`.
  @JsonKey(includeIfNull: false,name: 'vat_category')
  final String? vatCategory;

  /// Explicit VAT rate (kept for backwards compatibility). If `vat_category` / `vat_rate_override`.
  /// are omitted, resolved via country rules and only treated as an override if no category matches.
  @JsonKey(includeIfNull: false,name: 'vat_rate')
  final String? vatRate;

  /// Optional explicit VAT rate override (null clears any previous override).
  @JsonKey(includeIfNull: false,name: 'vat_rate_override')
  final String? vatRateOverride;
  @JsonKey(includeIfNull: false,name: 'weight_g')
  final int? weightG;
  @JsonKey(includeIfNull: false,name: 'width_mm')
  final int? widthMm;

  Map<String, Object?> toJson() => _$ProductInputToJson(this);
}
