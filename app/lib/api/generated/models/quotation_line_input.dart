// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'percent_base.dart';

part 'quotation_line_input.g.dart';

@JsonSerializable()
class QuotationLineInput {
  const QuotationLineInput({
    required this.productId,
    required this.quantity,
    this.addOptions,
    this.comment,
    this.customerRemark,
    this.customerRemarkLanguage,
    this.description,
    this.favoriteItemId,
    this.lineDiscountPercent,
    this.parentPosition,
    this.percentBase,
    this.percentOfParent,
    this.productionRemark,
    this.section,
    this.unitPrice,
  });

  factory QuotationLineInput.fromJson(Map<String, Object?> json) =>
      _$QuotationLineInputFromJson(json);

  /// Also adds the required options of the product as option lines directly below this line.
  /// (quantity: this line's quantity times the option's default quantity), unless the product is.
  /// already an option line of this line. Not stored: send the resulting lines on later saves.
  @JsonKey(includeIfNull: false, name: 'add_options')
  final bool? addOptions;

  /// Extra text printed below the line on the document.
  @JsonKey(includeIfNull: false)
  final String? comment;

  /// Remark printed under the description on the quotation and order documents.
  @JsonKey(includeIfNull: false, name: 'customer_remark')
  final String? customerRemark;

  /// The language (nl | fr | en | de | es) the customer remark is written in. Absent: it matches.
  /// the quotation language, or unknown. Ignored (stored empty) when the remark is empty.
  @JsonKey(includeIfNull: false, name: 'customer_remark_language')
  final String? customerRemarkLanguage;

  /// Overrides the product name on the document.
  @JsonKey(includeIfNull: false)
  final String? description;

  /// The favorite item this line was loaded from (of the caller's company, else 422), so that a.
  /// translation can be added to the favorite later. Copied by revisions, not by orders.
  @JsonKey(includeIfNull: false, name: 'favorite_item_id')
  final String? favoriteItemId;
  @JsonKey(includeIfNull: false, name: 'line_discount_percent')
  final String? lineDiscountPercent;

  /// Makes this an option or sub-line of an earlier line: the 1-based position of that line in.
  /// this list. Omitted: a top-level line.
  @JsonKey(includeIfNull: false, name: 'parent_position')
  final int? parentPosition;

  /// Which parent price `percent_of_parent` applies to; defaults to `parent_list_unit_price`.
  @JsonKey(includeIfNull: false, name: 'percent_base')
  final PercentBase? percentBase;

  /// Prices the line as this percentage (0 to 1000, 3 decimals) of its parent line's unit price.
  /// instead of the product's own price. Needs `parent_position`; not combined with `unit_price`.
  @JsonKey(includeIfNull: false, name: 'percent_of_parent')
  final String? percentOfParent;
  @JsonKey(name: 'product_id')
  final String productId;

  /// Internal remark for production; never printed for or shown to the customer. When empty,.
  /// the product's default production remark is used.
  @JsonKey(includeIfNull: false, name: 'production_remark')
  final String? productionRemark;
  final String quantity;

  /// Heading the line is grouped under on the document. A sub-line without a section is shown.
  /// under its parent's section.
  @JsonKey(includeIfNull: false)
  final String? section;

  /// Confirmed unit price (before rebates) for an indicative product. Indicative lines must be.
  /// confirmed before the quotation can be sent. Not allowed for other products.
  @JsonKey(includeIfNull: false, name: 'unit_price')
  final String? unitPrice;

  Map<String, Object?> toJson() => _$QuotationLineInputToJson(this);
}
