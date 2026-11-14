// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'repricing_line.g.dart';

/// One line of a quotation compared with today's prices.
@JsonSerializable()
class RepricingLine {
  const RepricingLine({
    required this.description,
    required this.difference,
    required this.needsConfirmation,
    required this.newLineTotal,
    required this.newListUnitPrice,
    required this.newRebatePercent,
    required this.oldLineTotal,
    required this.oldListUnitPrice,
    required this.oldRebatePercent,
    required this.position,
    required this.pricingType,
    required this.productCode,
    required this.quantity,
  });
  
  factory RepricingLine.fromJson(Map<String, Object?> json) => _$RepricingLineFromJson(json);
  
  final String description;
  final String difference;

  /// The new price is an indicative suggestion that must be confirmed.
  @JsonKey(name: 'needs_confirmation')
  final bool needsConfirmation;
  @JsonKey(name: 'new_line_total')
  final String newLineTotal;
  @JsonKey(name: 'new_list_unit_price')
  final String newListUnitPrice;
  @JsonKey(name: 'new_rebate_percent')
  final String newRebatePercent;
  @JsonKey(name: 'old_line_total')
  final String oldLineTotal;
  @JsonKey(name: 'old_list_unit_price')
  final String oldListUnitPrice;
  @JsonKey(name: 'old_rebate_percent')
  final String oldRebatePercent;
  final int position;
  @JsonKey(name: 'pricing_type')
  final String pricingType;
  @JsonKey(name: 'product_code')
  final String productCode;
  final String quantity;

  Map<String, Object?> toJson() => _$RepricingLineToJson(this);
}
