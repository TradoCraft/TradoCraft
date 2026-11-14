// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'goods_receipt_summary.g.dart';

/// Goods receipt header.
@JsonSerializable()
class GoodsReceiptSummary {
  const GoodsReceiptSummary({
    required this.carrier,
    required this.companyId,
    required this.createdAt,
    required this.id,
    required this.locationId,
    required this.notes,
    required this.number,
    required this.purchaseOrderId,
    required this.purchaseOrderNumber,
    required this.receivedByUserId,
    required this.receivedDate,
    required this.supplierDeliveryNote,
    required this.supplierName,
    required this.trackingNumber,
    required this.warehouseId,
  });
  
  factory GoodsReceiptSummary.fromJson(Map<String, Object?> json) => _$GoodsReceiptSummaryFromJson(json);
  
  final String carrier;
  @JsonKey(name: 'company_id')
  final String companyId;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  @JsonKey(name: 'location_id')
  final String locationId;
  final String notes;
  final String number;
  @JsonKey(name: 'purchase_order_id')
  final String purchaseOrderId;
  @JsonKey(name: 'purchase_order_number')
  final String purchaseOrderNumber;
  @JsonKey(name: 'received_by_user_id')
  final String receivedByUserId;
  @JsonKey(name: 'received_date')
  final DateTime receivedDate;
  @JsonKey(name: 'supplier_delivery_note')
  final String supplierDeliveryNote;
  @JsonKey(name: 'supplier_name')
  final String supplierName;
  @JsonKey(name: 'tracking_number')
  final String trackingNumber;
  @JsonKey(name: 'warehouse_id')
  final String warehouseId;

  Map<String, Object?> toJson() => _$GoodsReceiptSummaryToJson(this);
}
