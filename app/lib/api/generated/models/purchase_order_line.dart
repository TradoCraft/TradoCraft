// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'purchase_order_line.g.dart';

/// A purchase order line with received quantity.
@JsonSerializable()
class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.createdAt,
    required this.description,
    required this.id,
    required this.lineNumber,
    required this.lineTotal,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.purchaseOrderId,
    required this.quantity,
    required this.quantityReceived,
    required this.supplierProductCode,
    required this.unitPrice,
  });
  
  factory PurchaseOrderLine.fromJson(Map<String, Object?> json) => _$PurchaseOrderLineFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String description;
  final String id;
  @JsonKey(name: 'line_number')
  final int lineNumber;
  @JsonKey(name: 'line_total')
  final String lineTotal;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'purchase_order_id')
  final String purchaseOrderId;
  final String quantity;
  @JsonKey(name: 'quantity_received')
  final String quantityReceived;
  @JsonKey(name: 'supplier_product_code')
  final String supplierProductCode;
  @JsonKey(name: 'unit_price')
  final String unitPrice;

  Map<String, Object?> toJson() => _$PurchaseOrderLineToJson(this);
}
