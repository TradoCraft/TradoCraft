// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'order_summary.g.dart';

@JsonSerializable()
class OrderSummary {
  const OrderSummary({
    required this.currency,
    required this.currentRevision,
    required this.customerId,
    required this.customerName,
    required this.customerReference,
    required this.id,
    required this.number,
    required this.orderDate,
    required this.priority,
    required this.purpose,
    required this.quotationId,
    required this.quotationNumber,
    required this.quotationRevision,
    required this.salespersonId,
    required this.salespersonName,
    required this.status,
    required this.subtotal,
    required this.total,
    this.deliveryCountryCode,
    this.powerGridId,
    this.promisedDate,
  });
  
  factory OrderSummary.fromJson(Map<String, Object?> json) => _$OrderSummaryFromJson(json);
  
  final String currency;

  /// The latest revision.
  @JsonKey(name: 'current_revision')
  final int currentRevision;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(name: 'customer_reference')
  final String customerReference;

  /// Country the goods are delivered to (ISO alpha-2).
  @JsonKey(includeIfNull: false,name: 'delivery_country_code')
  final String? deliveryCountryCode;
  final String id;
  final String number;
  @JsonKey(name: 'order_date')
  final DateTime orderDate;

  /// The grid at the delivery country the goods are connected to (copied from the quotation).
  @JsonKey(includeIfNull: false,name: 'power_grid_id')
  final String? powerGridId;

  /// low | normal | expedite
  final String priority;

  /// When production expects the goods to be ready: the latest planned-ready date of the order's.
  /// production orders (ADR 0036). Empty until production has planned it.
  @JsonKey(includeIfNull: false,name: 'promised_date')
  final DateTime? promisedDate;

  /// installation | stock. Locked once the order is confirmed.
  final String purpose;
  @JsonKey(name: 'quotation_id')
  final String quotationId;
  @JsonKey(name: 'quotation_number')
  final String quotationNumber;
  @JsonKey(name: 'quotation_revision')
  final int quotationRevision;
  @JsonKey(name: 'salesperson_id')
  final String salespersonId;
  @JsonKey(name: 'salesperson_name')
  final String salespersonName;

  /// draft | sent | confirmed | in_planning | planned | in_production | ready_for_shipping |.
  /// partially_shipped | shipped | cancelled.
  final String status;
  final String subtotal;
  final String total;

  Map<String, Object?> toJson() => _$OrderSummaryToJson(this);
}
