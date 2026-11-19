// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'quotation_line.g.dart';

@JsonSerializable()
class QuotationLine {
  const QuotationLine({
    required this.description,
    required this.lineDiscountPercent,
    required this.lineTotal,
    required this.listUnitPrice,
    required this.netUnitPrice,
    required this.nonDiscountable,
    required this.position,
    required this.priceConfirmed,
    required this.priceIsIndicative,
    required this.priceOnRequest,
    required this.productCode,
    required this.quantity,
    required this.rebatePercent,
    required this.rebateSource,
    required this.unit,
    required this.vatRate,
    this.comment,
    this.customerRemark,
    this.customerRemarkLanguage,
    this.favoriteItemId,
    this.parentPosition,
    this.percentBase,
    this.percentOfParent,
    this.productId,
    this.productionRemark,
    this.section,
  });
  
  factory QuotationLine.fromJson(Map<String, Object?> json) => _$QuotationLineFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? comment;

  /// Remark printed under the description on the documents.
  @JsonKey(includeIfNull: false,name: 'customer_remark')
  final String? customerRemark;

  /// Language the customer remark is written in; absent: the quotation language, or unknown.
  @JsonKey(includeIfNull: false,name: 'customer_remark_language')
  final String? customerRemarkLanguage;
  final String description;

  /// The favorite item the line was loaded from; absent when it was not, or the favorite was deleted.
  @JsonKey(includeIfNull: false,name: 'favorite_item_id')
  final String? favoriteItemId;
  @JsonKey(name: 'line_discount_percent')
  final String lineDiscountPercent;
  @JsonKey(name: 'line_total')
  final String lineTotal;

  /// Zone list price, or the entered price of a price-on-request product (zero until entered).
  @JsonKey(name: 'list_unit_price')
  final String listUnitPrice;
  @JsonKey(name: 'net_unit_price')
  final String netUnitPrice;

  /// Never discounted: no rebate and no line discount.
  @JsonKey(name: 'non_discountable')
  final bool nonDiscountable;

  /// Position of the parent line (this is an option or sub-line of it).
  @JsonKey(includeIfNull: false,name: 'parent_position')
  final int? parentPosition;

  /// parent_list_unit_price | parent_net_unit_price
  @JsonKey(includeIfNull: false,name: 'percent_base')
  final String? percentBase;

  /// Set when the line is priced as a percentage of its parent line.
  @JsonKey(includeIfNull: false,name: 'percent_of_parent')
  final String? percentOfParent;
  final int position;

  /// False for a price-on-request line whose price has not been entered yet.
  @JsonKey(name: 'price_confirmed')
  final bool priceConfirmed;

  /// The list price is printed as indicative.
  @JsonKey(name: 'price_is_indicative')
  final bool priceIsIndicative;

  /// The product has no list price; the price is entered on the line.
  @JsonKey(name: 'price_on_request')
  final bool priceOnRequest;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// Internal remark for production (never printed for customers).
  @JsonKey(includeIfNull: false,name: 'production_remark')
  final String? productionRemark;
  final String quantity;

  /// Customer rebate applied to this line.
  @JsonKey(name: 'rebate_percent')
  final String rebatePercent;

  /// Where the rebate comes from: product | family | general | net
  @JsonKey(name: 'rebate_source')
  final String rebateSource;
  @JsonKey(includeIfNull: false)
  final String? section;
  final String unit;
  @JsonKey(name: 'vat_rate')
  final String vatRate;

  Map<String, Object?> toJson() => _$QuotationLineToJson(this);
}
