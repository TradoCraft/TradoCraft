// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'delivery_summary.g.dart';

@JsonSerializable()
class DeliverySummary {
  const DeliverySummary({
    required this.carrier,
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    required this.id,
    required this.lineCount,
    required this.number,
    required this.orderId,
    required this.orderNumber,
    required this.plannedOnClosure,
    required this.status,
    required this.trackingNumber,
    this.plannedDate,
    this.shippedAt,
  });
  
  factory DeliverySummary.fromJson(Map<String, Object?> json) => _$DeliverySummaryFromJson(json);
  
  final String carrier;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  final String id;
  @JsonKey(name: 'line_count')
  final int lineCount;
  final String number;
  @JsonKey(name: 'order_id')
  final String orderId;
  @JsonKey(name: 'order_number')
  final String orderNumber;
  @JsonKey(includeIfNull: false,name: 'planned_date')
  final DateTime? plannedDate;
  @JsonKey(name: 'planned_on_closure')
  final bool plannedOnClosure;
  @JsonKey(includeIfNull: false,name: 'shipped_at')
  final DateTime? shippedAt;

  /// planned | shipped | cancelled
  final String status;
  @JsonKey(name: 'tracking_number')
  final String trackingNumber;

  Map<String, Object?> toJson() => _$DeliverySummaryToJson(this);
}
