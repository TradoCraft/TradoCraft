// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'opportunity_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OpportunityInput _$OpportunityInputFromJson(Map<String, dynamic> json) =>
    OpportunityInput(
      customerId: json['customer_id'] as String,
      title: json['title'] as String,
      clearPowerGrid: json['clear_power_grid'] as bool?,
      expectedClose: json['expected_close'] == null
          ? null
          : DateTime.parse(json['expected_close'] as String),
      expectedValue: json['expected_value'] as String?,
      notes: json['notes'] as String?,
      ownerUserId: json['owner_user_id'] as String?,
      powerGridId: json['power_grid_id'] as String?,
      probability: (json['probability'] as num?)?.toInt(),
    );

Map<String, dynamic> _$OpportunityInputToJson(OpportunityInput instance) =>
    <String, dynamic>{
      'clear_power_grid': ?instance.clearPowerGrid,
      'customer_id': instance.customerId,
      'expected_close': ?instance.expectedClose?.toIso8601String(),
      'expected_value': ?instance.expectedValue,
      'notes': ?instance.notes,
      'owner_user_id': ?instance.ownerUserId,
      'power_grid_id': ?instance.powerGridId,
      'probability': ?instance.probability,
      'title': instance.title,
    };
