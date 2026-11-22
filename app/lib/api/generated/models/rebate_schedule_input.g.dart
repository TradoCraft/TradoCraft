// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_schedule_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateScheduleInput _$RebateScheduleInputFromJson(Map<String, dynamic> json) =>
    RebateScheduleInput(
      effectiveYear: (json['effective_year'] as num).toInt(),
      name: json['name'] as String,
      tiers: (json['tiers'] as List<dynamic>)
          .map((e) => RebateTier.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$RebateScheduleInputToJson(
  RebateScheduleInput instance,
) => <String, dynamic>{
  'effective_year': instance.effectiveYear,
  'name': instance.name,
  'tiers': instance.tiers,
};
