// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_centre_hours_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkCentreHoursInput _$WorkCentreHoursInputFromJson(
  Map<String, dynamic> json,
) => WorkCentreHoursInput(
  slots: (json['slots'] as List<dynamic>)
      .map((e) => WorkCentreHoursSlot.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$WorkCentreHoursInputToJson(
  WorkCentreHoursInput instance,
) => <String, dynamic>{'slots': instance.slots};
