// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionOrder _$ProductionOrderFromJson(Map<String, dynamic> json) =>
    ProductionOrder(
      quantity: json['quantity'] as String,
      bomRevision: (json['bom_revision'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      id: json['id'] as String,
      number: json['number'] as String,
      operationCount: (json['operation_count'] as num).toInt(),
      operationsDone: (json['operations_done'] as num).toInt(),
      orderCancelled: json['order_cancelled'] as bool,
      behindSchedule: json['behind_schedule'] as bool,
      priority: json['priority'] as String,
      productCode: json['product_code'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      productTracking: json['product_tracking'] as String,
      shortComponents: (json['short_components'] as num).toInt(),
      status: json['status'] as String,
      components: (json['components'] as List<dynamic>)
          .map((e) => ProductionComponent.fromJson(e as Map<String, dynamic>))
          .toList(),
      subOrders: (json['sub_orders'] as List<dynamic>)
          .map((e) => ProductionSubOrder.fromJson(e as Map<String, dynamic>))
          .toList(),
      notes: json['notes'] as String,
      unit: json['unit'] as String,
      outputs: (json['outputs'] as List<dynamic>)
          .map((e) => ProductionOutput.fromJson(e as Map<String, dynamic>))
          .toList(),
      operations: (json['operations'] as List<dynamic>)
          .map((e) => ProductionOperation.fromJson(e as Map<String, dynamic>))
          .toList(),
      plannedReadyDate: json['planned_ready_date'] == null
          ? null
          : DateTime.parse(json['planned_ready_date'] as String),
      actualCost: json['actual_cost'] == null
          ? null
          : ProductionOrderCost.fromJson(
              json['actual_cost'] as Map<String, dynamic>,
            ),
      cancelReason: json['cancel_reason'] as String?,
      orderNumber: json['order_number'] as String?,
      completedQuantity: json['completed_quantity'] as String?,
      orderId: json['order_id'] as String?,
      divisionName: json['division_name'] as String?,
      divisionId: json['division_id'] as String?,
      orderLineId: json['order_line_id'] as String?,
      customerName: json['customer_name'] as String?,
      parentOrderId: json['parent_order_id'] as String?,
      parentOrderNumber: json['parent_order_number'] as String?,
      plannedCost: json['planned_cost'] == null
          ? null
          : ProductionOrderCost.fromJson(
              json['planned_cost'] as Map<String, dynamic>,
            ),
      productionRemark: json['production_remark'] as String?,
      scheduledEnd: json['scheduled_end'] == null
          ? null
          : DateTime.parse(json['scheduled_end'] as String),
      startedAt: json['started_at'] == null
          ? null
          : DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
    );

Map<String, dynamic> _$ProductionOrderToJson(ProductionOrder instance) =>
    <String, dynamic>{
      'behind_schedule': instance.behindSchedule,
      'bom_revision': instance.bomRevision,
      'created_at': instance.createdAt.toIso8601String(),
      'customer_name': ?instance.customerName,
      'division_id': ?instance.divisionId,
      'division_name': ?instance.divisionName,
      'id': instance.id,
      'number': instance.number,
      'operation_count': instance.operationCount,
      'operations_done': instance.operationsDone,
      'order_cancelled': instance.orderCancelled,
      'order_id': ?instance.orderId,
      'order_number': ?instance.orderNumber,
      'planned_ready_date': ?instance.plannedReadyDate?.toIso8601String(),
      'priority': instance.priority,
      'product_code': instance.productCode,
      'product_id': instance.productId,
      'product_name': instance.productName,
      'product_tracking': instance.productTracking,
      'quantity': instance.quantity,
      'short_components': instance.shortComponents,
      'status': instance.status,
      'unit': instance.unit,
      'actual_cost': ?instance.actualCost,
      'cancel_reason': ?instance.cancelReason,
      'completed_at': ?instance.completedAt?.toIso8601String(),
      'completed_quantity': ?instance.completedQuantity,
      'components': instance.components,
      'notes': instance.notes,
      'operations': instance.operations,
      'order_line_id': ?instance.orderLineId,
      'outputs': instance.outputs,
      'parent_order_id': ?instance.parentOrderId,
      'parent_order_number': ?instance.parentOrderNumber,
      'planned_cost': ?instance.plannedCost,
      'production_remark': ?instance.productionRemark,
      'scheduled_end': ?instance.scheduledEnd?.toIso8601String(),
      'started_at': ?instance.startedAt?.toIso8601String(),
      'sub_orders': instance.subOrders,
    };
