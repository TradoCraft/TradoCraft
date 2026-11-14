// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_line_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InvoiceLineInput _$InvoiceLineInputFromJson(Map<String, dynamic> json) =>
    InvoiceLineInput(
      quantity: json['quantity'] as String,
      unitPrice: json['unit_price'] as String,
      description: json['description'] as String?,
      productId: json['product_id'] as String?,
      purchaseOrderLineId: json['purchase_order_line_id'] as String?,
      vatRate: json['vat_rate'] as String?,
    );

Map<String, dynamic> _$InvoiceLineInputToJson(InvoiceLineInput instance) =>
    <String, dynamic>{
      'description': ?instance.description,
      'product_id': ?instance.productId,
      'purchase_order_line_id': ?instance.purchaseOrderLineId,
      'quantity': instance.quantity,
      'unit_price': instance.unitPrice,
      'vat_rate': ?instance.vatRate,
    };
