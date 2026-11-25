// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_board_operation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionBoardOperation _$ProductionBoardOperationFromJson(
  Map<String, dynamic> json,
) => ProductionBoardOperation(
  id: json['id'] as String,
  lateValue: json['late'] as bool,
  locked: json['locked'] as bool,
  name: json['name'] as String,
  orderNumber: json['order_number'] as String,
  plannedEnd: DateTime.parse(json['planned_end'] as String),
  plannedMinutes: (json['planned_minutes'] as num).toInt(),
  plannedStart: DateTime.parse(json['planned_start'] as String),
  position: (json['position'] as num).toInt(),
  productName: json['product_name'] as String,
  productionOrderId: json['production_order_id'] as String,
  status: json['status'] as String,
  workCentreId: json['work_centre_id'] as String,
  plannedReadyDate: json['planned_ready_date'] == null
      ? null
      : DateTime.parse(json['planned_ready_date'] as String),
  predecessorEnd: json['predecessor_end'] == null
      ? null
      : DateTime.parse(json['predecessor_end'] as String),
  successorStart: json['successor_start'] == null
      ? null
      : DateTime.parse(json['successor_start'] as String),
);

Map<String, dynamic> _$ProductionBoardOperationToJson(
  ProductionBoardOperation instance,
) => <String, dynamic>{
  'id': instance.id,
  'late': instance.lateValue,
  'locked': instance.locked,
  'name': instance.name,
  'order_number': instance.orderNumber,
  'planned_end': instance.plannedEnd.toIso8601String(),
  'planned_minutes': instance.plannedMinutes,
  'planned_ready_date': ?instance.plannedReadyDate?.toIso8601String(),
  'planned_start': instance.plannedStart.toIso8601String(),
  'position': instance.position,
  'predecessor_end': ?instance.predecessorEnd?.toIso8601String(),
  'product_name': instance.productName,
  'production_order_id': instance.productionOrderId,
  'status': instance.status,
  'successor_start': ?instance.successorStart?.toIso8601String(),
  'work_centre_id': instance.workCentreId,
};
