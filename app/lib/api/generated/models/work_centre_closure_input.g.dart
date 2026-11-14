// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_centre_closure_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkCentreClosureInput _$WorkCentreClosureInputFromJson(
  Map<String, dynamic> json,
) => WorkCentreClosureInput(
  fromDate: DateTime.parse(json['from_date'] as String),
  toDate: DateTime.parse(json['to_date'] as String),
  kind: json['kind'] as String?,
  note: json['note'] as String?,
  workCentreId: json['work_centre_id'] as String?,
);

Map<String, dynamic> _$WorkCentreClosureInputToJson(
  WorkCentreClosureInput instance,
) => <String, dynamic>{
  'from_date': instance.fromDate.toIso8601String(),
  'kind': ?instance.kind,
  'note': ?instance.note,
  'to_date': instance.toDate.toIso8601String(),
  'work_centre_id': ?instance.workCentreId,
};
