// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'opportunity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Opportunity _$OpportunityFromJson(Map<String, dynamic> json) => Opportunity(
  createdAt: DateTime.parse(json['created_at'] as String),
  customerId: json['customer_id'] as String,
  customerName: json['customer_name'] as String,
  expectedValue: json['expected_value'] as String,
  id: json['id'] as String,
  notes: json['notes'] as String,
  number: json['number'] as String,
  ownerName: json['owner_name'] as String,
  ownerUserId: json['owner_user_id'] as String,
  probability: (json['probability'] as num).toInt(),
  stage: OpportunityStage.fromJson(json['stage'] as String),
  title: json['title'] as String,
  updatedAt: DateTime.parse(json['updated_at'] as String),
  closedAt: json['closed_at'] == null
      ? null
      : DateTime.parse(json['closed_at'] as String),
  expectedClose: json['expected_close'] == null
      ? null
      : DateTime.parse(json['expected_close'] as String),
  lostReason: json['lost_reason'] as String?,
  powerGridId: json['power_grid_id'] as String?,
);

Map<String, dynamic> _$OpportunityToJson(Opportunity instance) =>
    <String, dynamic>{
      'closed_at': ?instance.closedAt?.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
      'customer_id': instance.customerId,
      'customer_name': instance.customerName,
      'expected_close': ?instance.expectedClose?.toIso8601String(),
      'expected_value': instance.expectedValue,
      'id': instance.id,
      'lost_reason': ?instance.lostReason,
      'notes': instance.notes,
      'number': instance.number,
      'owner_name': instance.ownerName,
      'owner_user_id': instance.ownerUserId,
      'power_grid_id': ?instance.powerGridId,
      'probability': instance.probability,
      'stage': instance.stage,
      'title': instance.title,
      'updated_at': instance.updatedAt.toIso8601String(),
    };
