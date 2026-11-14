// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report_schedule_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReportScheduleInput _$ReportScheduleInputFromJson(Map<String, dynamic> json) =>
    ReportScheduleInput(
      format: json['format'] as String,
      frequency: json['frequency'] as String,
      name: json['name'] as String,
      source: json['source'] as String,
      active: json['active'] as bool?,
      addresses: (json['addresses'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      dayOfMonth: (json['day_of_month'] as num?)?.toInt(),
      helpdesk: json['helpdesk'] == null
          ? null
          : HelpdeskReportSpec.fromJson(
              json['helpdesk'] as Map<String, dynamic>,
            ),
      reportId: json['report_id'] as String?,
      sendTime: json['send_time'] as String?,
      timeZone: json['time_zone'] as String?,
      userIds: (json['user_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      weekday: (json['weekday'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ReportScheduleInputToJson(
  ReportScheduleInput instance,
) => <String, dynamic>{
  'active': ?instance.active,
  'addresses': ?instance.addresses,
  'day_of_month': ?instance.dayOfMonth,
  'format': instance.format,
  'frequency': instance.frequency,
  'helpdesk': ?instance.helpdesk,
  'name': instance.name,
  'report_id': ?instance.reportId,
  'send_time': ?instance.sendTime,
  'source': instance.source,
  'time_zone': ?instance.timeZone,
  'user_ids': ?instance.userIds,
  'weekday': ?instance.weekday,
};
