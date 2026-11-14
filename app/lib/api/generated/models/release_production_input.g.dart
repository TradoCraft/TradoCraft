// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release_production_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReleaseProductionInput _$ReleaseProductionInputFromJson(
  Map<String, dynamic> json,
) => ReleaseProductionInput(
  autoReleaseSubassemblies: json['auto_release_subassemblies'] as bool?,
  divisionId: json['division_id'] as String?,
  notes: json['notes'] as String?,
  orderId: json['order_id'] as String?,
  orderLineId: json['order_line_id'] as String?,
  parentOrderId: json['parent_order_id'] as String?,
  plannedReadyDate: json['planned_ready_date'] == null
      ? null
      : DateTime.parse(json['planned_ready_date'] as String),
  productId: json['product_id'] as String?,
  quantity: json['quantity'] as String?,
  startDate: json['start_date'] == null
      ? null
      : DateTime.parse(json['start_date'] as String),
);

Map<String, dynamic> _$ReleaseProductionInputToJson(
  ReleaseProductionInput instance,
) => <String, dynamic>{
  'auto_release_subassemblies': ?instance.autoReleaseSubassemblies,
  'division_id': ?instance.divisionId,
  'notes': ?instance.notes,
  'order_id': ?instance.orderId,
  'order_line_id': ?instance.orderLineId,
  'parent_order_id': ?instance.parentOrderId,
  'planned_ready_date': ?instance.plannedReadyDate?.toIso8601String(),
  'product_id': ?instance.productId,
  'quantity': ?instance.quantity,
  'start_date': ?instance.startDate?.toIso8601String(),
};
