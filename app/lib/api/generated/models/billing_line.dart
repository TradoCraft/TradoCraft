// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'billing_line.g.dart';

@JsonSerializable()
class BillingLine {
  const BillingLine({
    required this.description,
    required this.grossTotal,
    required this.id,
    required this.netTotal,
    required this.netUnitPrice,
    required this.position,
    required this.productCode,
    required this.quantity,
    required this.unit,
    required this.vatRate,
    required this.vatTotal,
    this.creditableNetTotal,
    this.creditableQuantity,
    this.deliveryLineId,
    this.includedInTurnover,
    this.sourceInvoiceLineId,
  });
  
  factory BillingLine.fromJson(Map<String, Object?> json) => _$BillingLineFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'creditable_net_total')
  final String? creditableNetTotal;
  @JsonKey(includeIfNull: false,name: 'creditable_quantity')
  final String? creditableQuantity;
  @JsonKey(includeIfNull: false,name: 'delivery_line_id')
  final String? deliveryLineId;
  final String description;
  @JsonKey(name: 'gross_total')
  final String grossTotal;
  final String id;
  @JsonKey(includeIfNull: false,name: 'included_in_turnover')
  final bool? includedInTurnover;
  @JsonKey(name: 'net_total')
  final String netTotal;
  @JsonKey(name: 'net_unit_price')
  final String netUnitPrice;
  final int position;
  @JsonKey(name: 'product_code')
  final String productCode;
  final String quantity;
  @JsonKey(includeIfNull: false,name: 'source_invoice_line_id')
  final String? sourceInvoiceLineId;
  final String unit;
  @JsonKey(name: 'vat_rate')
  final String vatRate;
  @JsonKey(name: 'vat_total')
  final String vatTotal;

  Map<String, Object?> toJson() => _$BillingLineToJson(this);
}
