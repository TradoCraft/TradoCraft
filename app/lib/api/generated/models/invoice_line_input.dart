// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'invoice_line_input.g.dart';

/// A line of an invoice being created or replaced.
@JsonSerializable()
class InvoiceLineInput {
  const InvoiceLineInput({
    required this.quantity,
    required this.unitPrice,
    this.description,
    this.productId,
    this.purchaseOrderLineId,
    this.vatRate,
  });
  
  factory InvoiceLineInput.fromJson(Map<String, Object?> json) => _$InvoiceLineInputFromJson(json);
  
  /// Description; required for a free-text line, defaults to the product name otherwise.
  @JsonKey(includeIfNull: false)
  final String? description;

  /// Product for a free-text line; taken from the order line otherwise.
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// The purchase order line billed; requires the invoice to have a purchase order.
  @JsonKey(includeIfNull: false,name: 'purchase_order_line_id')
  final String? purchaseOrderLineId;

  /// Invoiced quantity (greater than zero, at most 4 decimals).
  final String quantity;

  /// Unit price excluding VAT (at most 4 decimals).
  @JsonKey(name: 'unit_price')
  final String unitPrice;

  /// VAT rate in percent, default 0.
  @JsonKey(includeIfNull: false,name: 'vat_rate')
  final String? vatRate;

  Map<String, Object?> toJson() => _$InvoiceLineInputToJson(this);
}
