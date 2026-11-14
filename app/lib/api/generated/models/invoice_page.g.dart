// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InvoicePage _$InvoicePageFromJson(Map<String, dynamic> json) => InvoicePage(
  items: (json['items'] as List<dynamic>)
      .map((e) => InvoiceSummary.fromJson(e as Map<String, dynamic>))
      .toList(),
  total: (json['total'] as num).toInt(),
);

Map<String, dynamic> _$InvoicePageToJson(InvoicePage instance) =>
    <String, dynamic>{'items': instance.items, 'total': instance.total};
