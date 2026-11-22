// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BillingLine _$BillingLineFromJson(Map<String, dynamic> json) => BillingLine(
  description: json['description'] as String,
  grossTotal: json['gross_total'] as String,
  id: json['id'] as String,
  netTotal: json['net_total'] as String,
  netUnitPrice: json['net_unit_price'] as String,
  position: (json['position'] as num).toInt(),
  productCode: json['product_code'] as String,
  quantity: json['quantity'] as String,
  unit: json['unit'] as String,
  vatRate: json['vat_rate'] as String,
  vatTotal: json['vat_total'] as String,
  creditableNetTotal: json['creditable_net_total'] as String?,
  creditableQuantity: json['creditable_quantity'] as String?,
  deliveryLineId: json['delivery_line_id'] as String?,
  includedInTurnover: json['included_in_turnover'] as bool?,
  sourceInvoiceLineId: json['source_invoice_line_id'] as String?,
);

Map<String, dynamic> _$BillingLineToJson(BillingLine instance) =>
    <String, dynamic>{
      'creditable_net_total': ?instance.creditableNetTotal,
      'creditable_quantity': ?instance.creditableQuantity,
      'delivery_line_id': ?instance.deliveryLineId,
      'description': instance.description,
      'gross_total': instance.grossTotal,
      'id': instance.id,
      'included_in_turnover': ?instance.includedInTurnover,
      'net_total': instance.netTotal,
      'net_unit_price': instance.netUnitPrice,
      'position': instance.position,
      'product_code': instance.productCode,
      'quantity': instance.quantity,
      'source_invoice_line_id': ?instance.sourceInvoiceLineId,
      'unit': instance.unit,
      'vat_rate': instance.vatRate,
      'vat_total': instance.vatTotal,
    };
