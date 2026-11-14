// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'repricing_line.dart';

part 'repricing_comparison.g.dart';

/// What would change if a quotation were repriced at today's prices.
@JsonSerializable()
class RepricingComparison {
  const RepricingComparison({
    required this.difference,
    required this.lines,
    required this.newPriceDate,
    required this.newSubtotal,
    required this.oldPriceDate,
    required this.oldSubtotal,
    this.oldShippingTotal,
    this.shippingRequoteNeeded,
  });
  
  factory RepricingComparison.fromJson(Map<String, Object?> json) => _$RepricingComparisonFromJson(json);
  
  final String difference;
  final List<RepricingLine> lines;
  @JsonKey(name: 'new_price_date')
  final DateTime newPriceDate;
  @JsonKey(name: 'new_subtotal')
  final String newSubtotal;
  @JsonKey(name: 'old_price_date')
  final DateTime oldPriceDate;

  /// The shipping charge currently on the quotation (zero when it has none). Not part of the.
  /// subtotals above, which cover product lines only. The server always sends it; the schema marks.
  /// it optional so clients tolerate an older server, where an absent value means unknown.
  @JsonKey(includeIfNull: false,name: 'old_shipping_total')
  final String? oldShippingTotal;
  @JsonKey(name: 'old_subtotal')
  final String oldSubtotal;

  /// True when the quotation has a shipping line or its products require a shipping quote:.
  /// repricing means the shipping cost must be quoted again. The server always sends it; the schema.
  /// marks it optional so clients tolerate an older server, where an absent value means unknown.
  @JsonKey(includeIfNull: false,name: 'shipping_requote_needed')
  final bool? shippingRequoteNeeded;

  Map<String, Object?> toJson() => _$RepricingComparisonToJson(this);
}
