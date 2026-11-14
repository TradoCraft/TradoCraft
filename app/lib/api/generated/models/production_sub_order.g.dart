// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_sub_order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionSubOrder _$ProductionSubOrderFromJson(Map<String, dynamic> json) =>
    ProductionSubOrder(
      id: json['id'] as String,
      number: json['number'] as String,
      productCode: json['product_code'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      quantity: json['quantity'] as String,
      status: json['status'] as String,
      unit: json['unit'] as String,
      plannedReadyDate: json['planned_ready_date'] == null
          ? null
          : DateTime.parse(json['planned_ready_date'] as String),
      scheduledEnd: json['scheduled_end'] == null
          ? null
          : DateTime.parse(json['scheduled_end'] as String),
    );

Map<String, dynamic> _$ProductionSubOrderToJson(ProductionSubOrder instance) =>
    <String, dynamic>{
      'id': instance.id,
      'number': instance.number,
      'planned_ready_date': ?instance.plannedReadyDate?.toIso8601String(),
      'product_code': instance.productCode,
      'product_id': instance.productId,
      'product_name': instance.productName,
      'quantity': instance.quantity,
      'scheduled_end': ?instance.scheduledEnd?.toIso8601String(),
      'status': instance.status,
      'unit': instance.unit,
    };
