// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionSummary _$ProductionSummaryFromJson(Map<String, dynamic> json) =>
    ProductionSummary(
      behindSchedule: json['behind_schedule'] as bool,
      bomRevision: (json['bom_revision'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      id: json['id'] as String,
      number: json['number'] as String,
      operationCount: (json['operation_count'] as num).toInt(),
      operationsDone: (json['operations_done'] as num).toInt(),
      orderCancelled: json['order_cancelled'] as bool,
      priority: json['priority'] as String,
      productCode: json['product_code'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      productTracking: json['product_tracking'] as String,
      quantity: json['quantity'] as String,
      shortComponents: (json['short_components'] as num).toInt(),
      status: json['status'] as String,
      unit: json['unit'] as String,
      customerName: json['customer_name'] as String?,
      divisionId: json['division_id'] as String?,
      divisionName: json['division_name'] as String?,
      orderId: json['order_id'] as String?,
      orderNumber: json['order_number'] as String?,
      plannedReadyDate: json['planned_ready_date'] == null
          ? null
          : DateTime.parse(json['planned_ready_date'] as String),
    );

Map<String, dynamic> _$ProductionSummaryToJson(ProductionSummary instance) =>
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
    };
