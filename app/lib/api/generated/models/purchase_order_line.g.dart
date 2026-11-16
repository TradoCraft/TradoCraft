// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_order_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PurchaseOrderLine _$PurchaseOrderLineFromJson(Map<String, dynamic> json) =>
    PurchaseOrderLine(
      createdAt: DateTime.parse(json['created_at'] as String),
      description: json['description'] as String,
      id: json['id'] as String,
      lineNumber: (json['line_number'] as num).toInt(),
      lineTotal: json['line_total'] as String,
      productCode: json['product_code'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      purchaseOrderId: json['purchase_order_id'] as String,
      quantity: json['quantity'] as String,
      quantityReceived: json['quantity_received'] as String,
      supplierProductCode: json['supplier_product_code'] as String,
      unitPrice: json['unit_price'] as String,
      vatRate: json['vat_rate'] as String?,
    );

Map<String, dynamic> _$PurchaseOrderLineToJson(PurchaseOrderLine instance) =>
    <String, dynamic>{
      'created_at': instance.createdAt.toIso8601String(),
      'description': instance.description,
      'id': instance.id,
      'line_number': instance.lineNumber,
      'line_total': instance.lineTotal,
      'product_code': instance.productCode,
      'product_id': instance.productId,
      'product_name': instance.productName,
      'purchase_order_id': instance.purchaseOrderId,
      'quantity': instance.quantity,
      'quantity_received': instance.quantityReceived,
      'supplier_product_code': instance.supplierProductCode,
      'unit_price': instance.unitPrice,
      'vat_rate': ?instance.vatRate,
    };
