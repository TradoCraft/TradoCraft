// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'line_match.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LineMatch _$LineMatchFromJson(Map<String, dynamic> json) => LineMatch(
  invoiceLineId: json['invoice_line_id'] as String,
  invoiceUnitPrice: json['invoice_unit_price'] as String,
  issues: (json['issues'] as List<dynamic>)
      .map((e) => LineStatus.fromJson(e as String))
      .toList(),
  lineQuantity: json['line_quantity'] as String,
  status: LineStatus.fromJson(json['status'] as String),
  invoicedQuantity: json['invoiced_quantity'] as String?,
  orderedQuantity: json['ordered_quantity'] as String?,
  poUnitPrice: json['po_unit_price'] as String?,
  priceVariancePct: json['price_variance_pct'] as String?,
  receivedQuantity: json['received_quantity'] as String?,
);

Map<String, dynamic> _$LineMatchToJson(LineMatch instance) => <String, dynamic>{
  'invoice_line_id': instance.invoiceLineId,
  'invoice_unit_price': instance.invoiceUnitPrice,
  'invoiced_quantity': ?instance.invoicedQuantity,
  'issues': instance.issues,
  'line_quantity': instance.lineQuantity,
  'ordered_quantity': ?instance.orderedQuantity,
  'po_unit_price': ?instance.poUnitPrice,
  'price_variance_pct': ?instance.priceVariancePct,
  'received_quantity': ?instance.receivedQuantity,
  'status': instance.status,
};
