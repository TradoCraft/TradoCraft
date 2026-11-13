// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_summary.g.dart';

@JsonSerializable()
class ProductionSummary {
  const ProductionSummary({
    required this.behindSchedule,
    required this.bomRevision,
    required this.createdAt,
    required this.id,
    required this.number,
    required this.operationCount,
    required this.operationsDone,
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
    this.customerName,
    this.divisionId,
    this.divisionName,
    this.orderId,
    this.orderNumber,
    this.plannedReadyDate,
  });
  
  factory ProductionSummary.fromJson(Map<String, Object?> json) => _$ProductionSummaryFromJson(json);
  
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

  Map<String, Object?> toJson() => _$ProductionSummaryToJson(this);
}
