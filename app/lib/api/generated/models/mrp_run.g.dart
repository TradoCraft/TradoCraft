// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mrp_run.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MrpRun _$MrpRunFromJson(Map<String, dynamic> json) => MrpRun(
  createdAt: DateTime.parse(json['created_at'] as String),
  horizonDays: (json['horizon_days'] as num).toInt(),
  id: json['id'] as String,
  number: json['number'] as String,
  plannedOn: DateTime.parse(json['planned_on'] as String),
  proposals: (json['proposals'] as num).toInt(),
);

Map<String, dynamic> _$MrpRunToJson(MrpRun instance) => <String, dynamic>{
  'created_at': instance.createdAt.toIso8601String(),
  'horizon_days': instance.horizonDays,
  'id': instance.id,
  'number': instance.number,
  'planned_on': instance.plannedOn.toIso8601String(),
  'proposals': instance.proposals,
};
