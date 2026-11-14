// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_component.dart';
import 'production_output.dart';

part 'production_order.g.dart';

@JsonSerializable()
class ProductionOrder {
  const ProductionOrder({
    required this.bomRevision,
    required this.createdAt,
    required this.id,
    required this.number,
    required this.orderCancelled,
    required this.priority,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.productTracking,
    required this.quantity,
    required this.shortComponents,
    required this.status,
    required this.unit,
    required this.components,
    required this.notes,
    required this.outputs,
    this.customerName,
    this.divisionId,
    this.divisionName,
    this.orderId,
    this.orderNumber,
    this.plannedReadyDate,
    this.cancelReason,
    this.completedAt,
    this.completedQuantity,
    this.orderLineId,
    this.parentOrderId,
    this.startedAt,
  });

  factory ProductionOrder.fromJson(Map<String, Object?> json) =>
      _$ProductionOrderFromJson(json);

  @JsonKey(name: 'bom_revision')
  final int bomRevision;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false, name: 'customer_name')
  final String? customerName;
  @JsonKey(includeIfNull: false, name: 'division_id')
  final String? divisionId;
  @JsonKey(includeIfNull: false, name: 'division_name')
  final String? divisionName;
  final String id;
  final String number;

  /// The sales order was cancelled meanwhile: the planner should cancel this order too.
  @JsonKey(name: 'order_cancelled')
  final bool orderCancelled;
  @JsonKey(includeIfNull: false, name: 'order_id')
  final String? orderId;
  @JsonKey(includeIfNull: false, name: 'order_number')
  final String? orderNumber;
  @JsonKey(includeIfNull: false, name: 'planned_ready_date')
  final DateTime? plannedReadyDate;

  /// low | normal | expedite: the priority of the sales order (normal for stock).
  final String priority;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;

  /// none | serial | lot: what completion needs for the output.
  @JsonKey(name: 'product_tracking')
  final String productTracking;
  final String quantity;
  @JsonKey(name: 'short_components')
  final int shortComponents;

  /// released | in_progress | completed | cancelled
  final String status;
  final String unit;
  @JsonKey(includeIfNull: false, name: 'cancel_reason')
  final String? cancelReason;
  @JsonKey(includeIfNull: false, name: 'completed_at')
  final DateTime? completedAt;
  @JsonKey(includeIfNull: false, name: 'completed_quantity')
  final String? completedQuantity;
  final List<ProductionComponent> components;
  final String notes;
  @JsonKey(includeIfNull: false, name: 'order_line_id')
  final String? orderLineId;
  final List<ProductionOutput> outputs;
  @JsonKey(includeIfNull: false, name: 'parent_order_id')
  final String? parentOrderId;
  @JsonKey(includeIfNull: false, name: 'started_at')
  final DateTime? startedAt;

  Map<String, Object?> toJson() => _$ProductionOrderToJson(this);
}
