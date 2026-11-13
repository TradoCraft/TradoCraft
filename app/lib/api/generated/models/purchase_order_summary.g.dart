// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_order_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PurchaseOrderSummary _$PurchaseOrderSummaryFromJson(
  Map<String, dynamic> json,
) => PurchaseOrderSummary(
  companyId: json['company_id'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  createdByUserId: json['created_by_user_id'] as String,
  currency: json['currency'] as String,
  id: json['id'] as String,
  notes: json['notes'] as String,
  number: json['number'] as String,
  orderDate: DateTime.parse(json['order_date'] as String),
  sentTo: json['sent_to'] as String,
  status: json['status'] as String,
  subtotal: json['subtotal'] as String,
  supplierId: json['supplier_id'] as String,
  supplierName: json['supplier_name'] as String,
  taxTotal: json['tax_total'] as String,
  total: json['total'] as String,
  updatedAt: DateTime.parse(json['updated_at'] as String),
  approvedByUserId: json['approved_by_user_id'] as String?,
  expectedDeliveryDate: json['expected_delivery_date'] == null
      ? null
      : DateTime.parse(json['expected_delivery_date'] as String),
  sentAt: json['sent_at'] == null
      ? null
      : DateTime.parse(json['sent_at'] as String),
);

Map<String, dynamic> _$PurchaseOrderSummaryToJson(
  PurchaseOrderSummary instance,
) => <String, dynamic>{
  'approved_by_user_id': ?instance.approvedByUserId,
  'company_id': instance.companyId,
  'created_at': instance.createdAt.toIso8601String(),
  'created_by_user_id': instance.createdByUserId,
  'currency': instance.currency,
  'expected_delivery_date': ?instance.expectedDeliveryDate?.toIso8601String(),
  'id': instance.id,
  'notes': instance.notes,
  'number': instance.number,
  'order_date': instance.orderDate.toIso8601String(),
  'sent_at': ?instance.sentAt?.toIso8601String(),
  'sent_to': instance.sentTo,
  'status': instance.status,
  'subtotal': instance.subtotal,
  'supplier_id': instance.supplierId,
  'supplier_name': instance.supplierName,
  'tax_total': instance.taxTotal,
  'total': instance.total,
  'updated_at': instance.updatedAt.toIso8601String(),
};
