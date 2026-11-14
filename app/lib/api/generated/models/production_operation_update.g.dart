// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_operation_update.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionOperationUpdate _$ProductionOperationUpdateFromJson(
  Map<String, dynamic> json,
) => ProductionOperationUpdate(
  plannedEnd: json['planned_end'] == null
      ? null
      : DateTime.parse(json['planned_end'] as String),
  plannedStart: json['planned_start'] == null
      ? null
      : DateTime.parse(json['planned_start'] as String),
  workCentreId: json['work_centre_id'] as String?,
);

Map<String, dynamic> _$ProductionOperationUpdateToJson(
  ProductionOperationUpdate instance,
) => <String, dynamic>{
  'planned_end': ?instance.plannedEnd?.toIso8601String(),
  'planned_start': ?instance.plannedStart?.toIso8601String(),
  'work_centre_id': ?instance.workCentreId,
};
