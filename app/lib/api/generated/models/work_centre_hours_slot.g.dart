// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_centre_hours_slot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkCentreHoursSlot _$WorkCentreHoursSlotFromJson(Map<String, dynamic> json) =>
    WorkCentreHoursSlot(
      endTime: json['end_time'] as String,
      startTime: json['start_time'] as String,
      weekday: (json['weekday'] as num).toInt(),
    );

Map<String, dynamic> _$WorkCentreHoursSlotToJson(
  WorkCentreHoursSlot instance,
) => <String, dynamic>{
  'end_time': instance.endTime,
  'start_time': instance.startTime,
  'weekday': instance.weekday,
};
