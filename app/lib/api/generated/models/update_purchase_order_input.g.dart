// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_purchase_order_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdatePurchaseOrderInput _$UpdatePurchaseOrderInputFromJson(
  Map<String, dynamic> json,
) => UpdatePurchaseOrderInput(
  currency: json['currency'] as String?,
  expectedDeliveryDate: json['expected_delivery_date'] == null
      ? null
      : DateTime.parse(json['expected_delivery_date'] as String),
  lines: (json['lines'] as List<dynamic>?)
      ?.map((e) => NewPoLineInput.fromJson(e as Map<String, dynamic>))
      .toList(),
  notes: json['notes'] as String?,
);

Map<String, dynamic> _$UpdatePurchaseOrderInputToJson(
  UpdatePurchaseOrderInput instance,
) => <String, dynamic>{
  'currency': ?instance.currency,
  'expected_delivery_date': ?instance.expectedDeliveryDate?.toIso8601String(),
  'lines': ?instance.lines,
  'notes': ?instance.notes,
};
