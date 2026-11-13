// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_component.dart';
import 'production_operation.dart';
import 'production_order_cost.dart';
import 'production_output.dart';
import 'production_sub_order.dart';

part 'production_order.g.dart';

@JsonSerializable()
class ProductionOrder {
  const ProductionOrder({
    required this.quantity,
    required this.bomRevision,
    required this.createdAt,
    required this.id,
    required this.number,
    required this.operationCount,
    required this.operationsDone,
    required this.orderCancelled,
    required this.behindSchedule,
    required this.priority,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.productTracking,
    required this.shortComponents,
    required this.status,
    required this.components,
    required this.subOrders,
    required this.notes,
    required this.unit,
    required this.outputs,
    required this.operations,
    this.plannedReadyDate,
    this.actualCost,
    this.cancelReason,
    this.orderNumber,
    this.completedQuantity,
    this.orderId,
    this.divisionName,
    this.divisionId,
    this.orderLineId,
    this.customerName,
    this.parentOrderId,
    this.parentOrderNumber,
    this.plannedCost,
    this.productionRemark,
    this.scheduledEnd,
    this.startedAt,
    this.completedAt,
  });
  
  factory ProductionOrder.fromJson(Map<String, Object?> json) => _$ProductionOrderFromJson(json);
  
  /// An operation that is not finished is scheduled after the planned-ready date.
  @JsonKey(name: 'behind_schedule')
  final bool behindSchedule;
  @JsonKey(name: 'bom_revision')
  final int bomRevision;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false,name: 'customer_name')
  final String? customerName;
  @JsonKey(includeIfNull: false,name: 'division_id')
  final String? divisionId;
  @JsonKey(includeIfNull: false,name: 'division_name')
  final String? divisionName;
  final String id;
  final String number;

  /// Operations of the routing that was frozen at release (0 without a routing).
  @JsonKey(name: 'operation_count')
  final int operationCount;

  /// How many of them are finished.
  @JsonKey(name: 'operations_done')
  final int operationsDone;

  /// The sales order was cancelled meanwhile: the planner should cancel this order too.
  @JsonKey(name: 'order_cancelled')
  final bool orderCancelled;
  @JsonKey(includeIfNull: false,name: 'order_id')
  final String? orderId;
  @JsonKey(includeIfNull: false,name: 'order_number')
  final String? orderNumber;
  @JsonKey(includeIfNull: false,name: 'planned_ready_date')
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

  /// What it cost so far: the components consumed (booked when the order is completed) and the.
  /// minutes of the finished operations. Only for users who may see cost, once it has started.
  /// (also when it was cancelled afterwards).
  @JsonKey(includeIfNull: false,name: 'actual_cost')
  final ProductionOrderCost? actualCost;
  @JsonKey(includeIfNull: false,name: 'cancel_reason')
  final String? cancelReason;
  @JsonKey(includeIfNull: false,name: 'completed_at')
  final DateTime? completedAt;
  @JsonKey(includeIfNull: false,name: 'completed_quantity')
  final String? completedQuantity;
  final List<ProductionComponent> components;
  final String notes;
  final List<ProductionOperation> operations;
  @JsonKey(includeIfNull: false,name: 'order_line_id')
  final String? orderLineId;
  final List<ProductionOutput> outputs;
  @JsonKey(includeIfNull: false,name: 'parent_order_id')
  final String? parentOrderId;

  /// The number of the production order this one is a subassembly of.
  @JsonKey(includeIfNull: false,name: 'parent_order_number')
  final String? parentOrderNumber;

  /// What the order is planned to cost: components at the standard cost frozen at release and.
  /// operations at their planned minutes. Only for users who may see cost.
  @JsonKey(includeIfNull: false,name: 'planned_cost')
  final ProductionOrderCost? plannedCost;

  /// The internal production remark of the sales order line it builds for (never printed for.
  /// the customer).
  @JsonKey(includeIfNull: false,name: 'production_remark')
  final String? productionRemark;

  /// When the last operation that is not finished is scheduled to end: the date to suggest as.
  /// the planned-ready date. Empty without open operations.
  @JsonKey(includeIfNull: false,name: 'scheduled_end')
  final DateTime? scheduledEnd;
  @JsonKey(includeIfNull: false,name: 'started_at')
  final DateTime? startedAt;

  /// The production orders released for its subassemblies.
  @JsonKey(name: 'sub_orders')
  final List<ProductionSubOrder> subOrders;

  Map<String, Object?> toJson() => _$ProductionOrderToJson(this);
}
