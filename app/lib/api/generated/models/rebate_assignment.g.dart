// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_assignment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateAssignment _$RebateAssignmentFromJson(Map<String, dynamic> json) =>
    RebateAssignment(
      customerId: json['customer_id'] as String,
      scheduleName: json['schedule_name'] as String?,
    );

Map<String, dynamic> _$RebateAssignmentToJson(RebateAssignment instance) =>
    <String, dynamic>{
      'customer_id': instance.customerId,
      'schedule_name': ?instance.scheduleName,
    };
