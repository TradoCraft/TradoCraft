// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_centre_closure.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkCentreClosure _$WorkCentreClosureFromJson(Map<String, dynamic> json) =>
    WorkCentreClosure(
      fromDate: DateTime.parse(json['from_date'] as String),
      id: json['id'] as String,
      kind: json['kind'] as String,
      note: json['note'] as String,
      toDate: DateTime.parse(json['to_date'] as String),
      workCentreCode: json['work_centre_code'] as String?,
      workCentreId: json['work_centre_id'] as String?,
    );

Map<String, dynamic> _$WorkCentreClosureToJson(WorkCentreClosure instance) =>
    <String, dynamic>{
      'from_date': instance.fromDate.toIso8601String(),
      'id': instance.id,
      'kind': instance.kind,
      'note': instance.note,
      'to_date': instance.toDate.toIso8601String(),
      'work_centre_code': ?instance.workCentreCode,
      'work_centre_id': ?instance.workCentreId,
    };
