// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderSummary _$OrderSummaryFromJson(Map<String, dynamic> json) => OrderSummary(
  currency: json['currency'] as String,
  currentRevision: (json['current_revision'] as num).toInt(),
  customerId: json['customer_id'] as String,
  customerName: json['customer_name'] as String,
  customerReference: json['customer_reference'] as String,
  id: json['id'] as String,
  number: json['number'] as String,
  orderDate: DateTime.parse(json['order_date'] as String),
  priority: json['priority'] as String,
  purpose: json['purpose'] as String,
  quotationId: json['quotation_id'] as String,
  quotationNumber: json['quotation_number'] as String,
  quotationRevision: (json['quotation_revision'] as num).toInt(),
  salespersonId: json['salesperson_id'] as String,
  salespersonName: json['salesperson_name'] as String,
  status: json['status'] as String,
  subtotal: json['subtotal'] as String,
  total: json['total'] as String,
  buildingConstructionYear: (json['building_construction_year'] as num?)
      ?.toInt(),
  deliveryCountryCode: json['delivery_country_code'] as String?,
  powerGridId: json['power_grid_id'] as String?,
  promisedDate: json['promised_date'] == null
      ? null
      : DateTime.parse(json['promised_date'] as String),
  vatRegime: json['vat_regime'] as String?,
);

Map<String, dynamic> _$OrderSummaryToJson(OrderSummary instance) =>
    <String, dynamic>{
      'building_construction_year': ?instance.buildingConstructionYear,
      'currency': instance.currency,
      'current_revision': instance.currentRevision,
      'customer_id': instance.customerId,
      'customer_name': instance.customerName,
      'customer_reference': instance.customerReference,
      'delivery_country_code': ?instance.deliveryCountryCode,
      'id': instance.id,
      'number': instance.number,
      'order_date': instance.orderDate.toIso8601String(),
      'power_grid_id': ?instance.powerGridId,
      'priority': instance.priority,
      'promised_date': ?instance.promisedDate?.toIso8601String(),
      'purpose': instance.purpose,
      'quotation_id': instance.quotationId,
      'quotation_number': instance.quotationNumber,
      'quotation_revision': instance.quotationRevision,
      'salesperson_id': instance.salespersonId,
      'salesperson_name': instance.salespersonName,
      'status': instance.status,
      'subtotal': instance.subtotal,
      'total': instance.total,
      'vat_regime': ?instance.vatRegime,
    };
