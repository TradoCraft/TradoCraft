// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InvoiceLine _$InvoiceLineFromJson(Map<String, dynamic> json) => InvoiceLine(
  description: json['description'] as String,
  id: json['id'] as String,
  invoiceId: json['invoice_id'] as String,
  lineGross: json['line_gross'] as String,
  lineNet: json['line_net'] as String,
  lineNumber: (json['line_number'] as num).toInt(),
  lineVat: json['line_vat'] as String,
  quantity: json['quantity'] as String,
  unitPrice: json['unit_price'] as String,
  vatRate: json['vat_rate'] as String,
  productId: json['product_id'] as String?,
  purchaseOrderLineId: json['purchase_order_line_id'] as String?,
);

Map<String, dynamic> _$InvoiceLineToJson(InvoiceLine instance) =>
    <String, dynamic>{
      'description': instance.description,
      'id': instance.id,
      'invoice_id': instance.invoiceId,
      'line_gross': instance.lineGross,
      'line_net': instance.lineNet,
      'line_number': instance.lineNumber,
      'line_vat': instance.lineVat,
      'product_id': ?instance.productId,
      'purchase_order_line_id': ?instance.purchaseOrderLineId,
      'quantity': instance.quantity,
      'unit_price': instance.unitPrice,
      'vat_rate': instance.vatRate,
    };
