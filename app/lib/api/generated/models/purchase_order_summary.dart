// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'purchase_order_summary.g.dart';

/// Purchase order header with supplier name and totals.
@JsonSerializable()
class PurchaseOrderSummary {
  const PurchaseOrderSummary({
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
    this.approvedByUserId,
    this.expectedDeliveryDate,
  });
  
  factory PurchaseOrderSummary.fromJson(Map<String, Object?> json) => _$PurchaseOrderSummaryFromJson(json);
  
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

  Map<String, Object?> toJson() => _$PurchaseOrderSummaryToJson(this);
}
