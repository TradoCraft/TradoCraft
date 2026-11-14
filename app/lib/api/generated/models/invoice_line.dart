// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'invoice_line.g.dart';

/// A supplier invoice line.
@JsonSerializable()
class InvoiceLine {
  const InvoiceLine({
    required this.description,
    required this.id,
    required this.invoiceId,
    required this.lineGross,
    required this.lineNet,
    required this.lineNumber,
    required this.lineVat,
    required this.quantity,
    required this.unitPrice,
    required this.vatRate,
    this.productId,
    this.purchaseOrderLineId,
  });
  
  factory InvoiceLine.fromJson(Map<String, Object?> json) => _$InvoiceLineFromJson(json);
  
  /// Description.
  final String description;

  /// Line id.
  final String id;

  /// Invoice id.
  @JsonKey(name: 'invoice_id')
  final String invoiceId;

  /// Net plus VAT.
  @JsonKey(name: 'line_gross')
  final String lineGross;

  /// Quantity times price, 2 decimals.
  @JsonKey(name: 'line_net')
  final String lineNet;

  /// Position on the invoice, from 1.
  @JsonKey(name: 'line_number')
  final int lineNumber;

  /// VAT on the net amount, 2 decimals.
  @JsonKey(name: 'line_vat')
  final String lineVat;

  /// Product, when known.
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// The purchase order line this line bills; `None` for a free-text line.
  @JsonKey(includeIfNull: false,name: 'purchase_order_line_id')
  final String? purchaseOrderLineId;

  /// Invoiced quantity.
  final String quantity;

  /// Unit price excluding VAT.
  @JsonKey(name: 'unit_price')
  final String unitPrice;

  /// VAT rate in percent.
  @JsonKey(name: 'vat_rate')
  final String vatRate;

  Map<String, Object?> toJson() => _$InvoiceLineToJson(this);
}
