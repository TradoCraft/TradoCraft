// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'goods_receipt_line.g.dart';

/// A received line of a goods receipt.
@JsonSerializable()
class GoodsReceiptLine {
  const GoodsReceiptLine({
    required this.createdAt,
    required this.goodsReceiptId,
    required this.id,
    required this.poLineId,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.quantityReceived,
    this.lotNumber,
  });
  
  factory GoodsReceiptLine.fromJson(Map<String, Object?> json) => _$GoodsReceiptLineFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'goods_receipt_id')
  final String goodsReceiptId;
  final String id;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  @JsonKey(name: 'po_line_id')
  final String poLineId;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'quantity_received')
  final String quantityReceived;

  Map<String, Object?> toJson() => _$GoodsReceiptLineToJson(this);
}
