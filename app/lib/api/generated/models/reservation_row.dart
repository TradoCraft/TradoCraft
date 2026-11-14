// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reservation_row.g.dart';

@JsonSerializable()
class ReservationRow {
  const ReservationRow({
    required this.consumedQuantity,
    required this.createdAt,
    required this.id,
    required this.location,
    required this.productCode,
    required this.productId,
    required this.quantity,
    required this.referenceId,
    required this.referenceType,
    this.customerName,
    this.lotNumber,
    this.orderId,
    this.orderLineId,
    this.orderNumber,
    this.position,
  });
  
  factory ReservationRow.fromJson(Map<String, Object?> json) => _$ReservationRowFromJson(json);
  
  /// Already shipped or consumed from this allocation.
  @JsonKey(name: 'consumed_quantity')
  final String consumedQuantity;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false,name: 'customer_name')
  final String? customerName;
  final String id;
  final String location;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;

  /// The order, for a sales order line.
  @JsonKey(includeIfNull: false,name: 'order_id')
  final String? orderId;
  @JsonKey(includeIfNull: false,name: 'order_line_id')
  final String? orderLineId;
  @JsonKey(includeIfNull: false,name: 'order_number')
  final String? orderNumber;
  @JsonKey(includeIfNull: false)
  final int? position;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;

  /// Still held.
  final String quantity;
  @JsonKey(name: 'reference_id')
  final String referenceId;

  /// sales_order_line | production_component
  @JsonKey(name: 'reference_type')
  final String referenceType;

  Map<String, Object?> toJson() => _$ReservationRowToJson(this);
}
