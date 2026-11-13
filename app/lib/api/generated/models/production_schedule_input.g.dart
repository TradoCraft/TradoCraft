// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_schedule_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionScheduleInput _$ProductionScheduleInputFromJson(
  Map<String, dynamic> json,
) => ProductionScheduleInput(
  startDate: json['start_date'] == null
      ? null
      : DateTime.parse(json['start_date'] as String),
);

Map<String, dynamic> _$ProductionScheduleInputToJson(
  ProductionScheduleInput instance,
) => <String, dynamic>{'start_date': ?instance.startDate?.toIso8601String()};
