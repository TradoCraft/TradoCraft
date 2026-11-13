// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'incoming_line.g.dart';

/// One open purchase order line that still has goods to come.
@JsonSerializable()
class IncomingLine {
  const IncomingLine({
    required this.openQuantity,
    required this.productId,
    required this.purchaseOrderId,
    required this.purchaseOrderNumber,
    this.expectedDeliveryDate,
  });
  
  factory IncomingLine.fromJson(Map<String, Object?> json) => _$IncomingLineFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'expected_delivery_date')
  final DateTime? expectedDeliveryDate;

  /// Ordered minus received, in the stock unit of the product.
  @JsonKey(name: 'open_quantity')
  final String openQuantity;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'purchase_order_id')
  final String purchaseOrderId;
  @JsonKey(name: 'purchase_order_number')
  final String purchaseOrderNumber;

  Map<String, Object?> toJson() => _$IncomingLineToJson(this);
}
