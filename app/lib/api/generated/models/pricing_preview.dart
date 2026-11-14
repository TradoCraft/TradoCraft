// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'quotation_line.dart';
import 'sales_suggestion.dart';
import 'sales_warning.dart';
import 'vat_group.dart';

part 'pricing_preview.g.dart';

/// Result of pricing lines without saving anything.
@JsonSerializable()
class PricingPreview {
  const PricingPreview({
    required this.customerDiscountPercent,
    required this.lines,
    required this.priceDate,
    required this.priceZoneCode,
    required this.quoteDate,
    required this.subtotal,
    required this.suggestions,
    required this.total,
    required this.unconfirmedLines,
    required this.vatGroups,
    required this.vatTotal,
    required this.warnings,
  });
  
  factory PricingPreview.fromJson(Map<String, Object?> json) => _$PricingPreviewFromJson(json);
  
  @JsonKey(name: 'customer_discount_percent')
  final String customerDiscountPercent;

  /// The priced product lines in input order, then (only when the input had a `quotation_id`.
  /// with a quoted shipping cost) the `SHIPPING` line, which has no `product_id`.
  final List<QuotationLine> lines;
  @JsonKey(name: 'price_date')
  final DateTime priceDate;
  @JsonKey(name: 'price_zone_code')
  final String priceZoneCode;
  @JsonKey(name: 'quote_date')
  final DateTime quoteDate;
  final String subtotal;

  /// Products worth adding (manual rules, then often bought together). Never blocking.
  final List<SalesSuggestion> suggestions;
  final String total;

  /// Indicative prices still to confirm; the quotation cannot be sent while this is not 0.
  @JsonKey(name: 'unconfirmed_lines')
  final int unconfirmedLines;
  @JsonKey(name: 'vat_groups')
  final List<VatGroup> vatGroups;
  @JsonKey(name: 'vat_total')
  final String vatTotal;

  /// Hints about the lines (power grid fit, incompatible products). Never blocking.
  final List<SalesWarning> warnings;

  Map<String, Object?> toJson() => _$PricingPreviewToJson(this);
}
