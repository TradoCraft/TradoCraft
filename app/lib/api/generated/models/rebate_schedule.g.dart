// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_schedule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateSchedule _$RebateScheduleFromJson(Map<String, dynamic> json) =>
    RebateSchedule(
      effectiveYear: (json['effective_year'] as num).toInt(),
      id: json['id'] as String,
      name: json['name'] as String,
      tiers: (json['tiers'] as List<dynamic>)
          .map((e) => RebateTier.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$RebateScheduleToJson(RebateSchedule instance) =>
    <String, dynamic>{
      'effective_year': instance.effectiveYear,
      'id': instance.id,
      'name': instance.name,
      'tiers': instance.tiers,
    };
