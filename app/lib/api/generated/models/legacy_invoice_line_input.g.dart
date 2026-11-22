// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'legacy_invoice_line_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LegacyInvoiceLineInput _$LegacyInvoiceLineInputFromJson(
  Map<String, dynamic> json,
) => LegacyInvoiceLineInput(
  description: json['description'] as String,
  includedInTurnover: json['included_in_turnover'] as bool,
  netTotal: json['net_total'] as String,
  productCode: json['product_code'] as String,
  quantity: json['quantity'] as String,
  unit: json['unit'] as String,
  vatRate: json['vat_rate'] as String,
  vatTotal: json['vat_total'] as String,
);

Map<String, dynamic> _$LegacyInvoiceLineInputToJson(
  LegacyInvoiceLineInput instance,
) => <String, dynamic>{
  'description': instance.description,
  'included_in_turnover': instance.includedInTurnover,
  'net_total': instance.netTotal,
  'product_code': instance.productCode,
  'quantity': instance.quantity,
  'unit': instance.unit,
  'vat_rate': instance.vatRate,
  'vat_total': instance.vatTotal,
};
