// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'incoming_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IncomingLine _$IncomingLineFromJson(Map<String, dynamic> json) => IncomingLine(
  openQuantity: json['open_quantity'] as String,
  productId: json['product_id'] as String,
  purchaseOrderId: json['purchase_order_id'] as String,
  purchaseOrderNumber: json['purchase_order_number'] as String,
  expectedDeliveryDate: json['expected_delivery_date'] == null
      ? null
      : DateTime.parse(json['expected_delivery_date'] as String),
);

Map<String, dynamic> _$IncomingLineToJson(
  IncomingLine instance,
) => <String, dynamic>{
  'expected_delivery_date': ?instance.expectedDeliveryDate?.toIso8601String(),
  'open_quantity': instance.openQuantity,
  'product_id': instance.productId,
  'purchase_order_id': instance.purchaseOrderId,
  'purchase_order_number': instance.purchaseOrderNumber,
};
