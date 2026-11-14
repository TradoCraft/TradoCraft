// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'purchase_order_line.dart';

part 'purchase_order_detail.g.dart';

/// Purchase order header together with its lines.
@JsonSerializable()
class PurchaseOrderDetail {
  const PurchaseOrderDetail({
    required this.companyId,
    required this.createdAt,
    required this.createdByUserId,
    required this.currency,
    required this.id,
    required this.notes,
    required this.number,
    required this.orderDate,
    required this.status,
    required this.subtotal,
    required this.supplierId,
    required this.supplierName,
    required this.taxTotal,
    required this.total,
    required this.updatedAt,
    required this.lines,
    this.approvedByUserId,
    this.expectedDeliveryDate,
  });
  
  factory PurchaseOrderDetail.fromJson(Map<String, Object?> json) => _$PurchaseOrderDetailFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'approved_by_user_id')
  final String? approvedByUserId;
  @JsonKey(name: 'company_id')
  final String companyId;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'created_by_user_id')
  final String createdByUserId;
  final String currency;
  @JsonKey(includeIfNull: false,name: 'expected_delivery_date')
  final DateTime? expectedDeliveryDate;
  final String id;
  final String notes;
  final String number;
  @JsonKey(name: 'order_date')
  final DateTime orderDate;

  /// draft | approved | sent | partially_received | received | cancelled
  final String status;
  final String subtotal;
  @JsonKey(name: 'supplier_id')
  final String supplierId;
  @JsonKey(name: 'supplier_name')
  final String supplierName;
  @JsonKey(name: 'tax_total')
  final String taxTotal;
  final String total;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
  final List<PurchaseOrderLine> lines;

  Map<String, Object?> toJson() => _$PurchaseOrderDetailToJson(this);
}
