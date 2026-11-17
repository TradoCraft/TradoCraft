// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_edit_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderEditInput _$OrderEditInputFromJson(Map<String, dynamic> json) =>
    OrderEditInput(
      lines: (json['lines'] as List<dynamic>)
          .map((e) => OrderLineEdit.fromJson(e as Map<String, dynamic>))
          .toList(),
      clearPowerGrid: json['clear_power_grid'] as bool?,
      customerReference: json['customer_reference'] as String?,
      deliveryCountryCode: json['delivery_country_code'] as String?,
      expectedVersion: (json['expected_version'] as num?)?.toInt(),
      notes: json['notes'] as String?,
      powerGridId: json['power_grid_id'] as String?,
      purpose: json['purpose'] as String?,
    );

Map<String, dynamic> _$OrderEditInputToJson(OrderEditInput instance) =>
    <String, dynamic>{
      'clear_power_grid': ?instance.clearPowerGrid,
      'customer_reference': ?instance.customerReference,
      'delivery_country_code': ?instance.deliveryCountryCode,
      'expected_version': ?instance.expectedVersion,
      'lines': instance.lines,
      'notes': ?instance.notes,
      'power_grid_id': ?instance.powerGridId,
      'purpose': ?instance.purpose,
    };
