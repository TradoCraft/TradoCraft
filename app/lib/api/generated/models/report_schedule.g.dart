// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report_schedule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReportSchedule _$ReportScheduleFromJson(
  Map<String, dynamic> json,
) => ReportSchedule(
  active: json['active'] as bool,
  addresses: (json['addresses'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  createdAt: DateTime.parse(json['created_at'] as String),
  format: json['format'] as String,
  frequency: json['frequency'] as String,
  id: json['id'] as String,
  name: json['name'] as String,
  nextRunAt: DateTime.parse(json['next_run_at'] as String),
  ownerId: json['owner_id'] as String,
  ownerName: json['owner_name'] as String,
  sendTime: json['send_time'] as String,
  source: json['source'] as String,
  timeZone: json['time_zone'] as String,
  updatedAt: DateTime.parse(json['updated_at'] as String),
  userIds: (json['user_ids'] as List<dynamic>).map((e) => e as String).toList(),
  dayOfMonth: (json['day_of_month'] as num?)?.toInt(),
  helpdesk: json['helpdesk'] == null
      ? null
      : HelpdeskReportSpec.fromJson(json['helpdesk'] as Map<String, dynamic>),
  lastError: json['last_error'] as String?,
  lastRunAt: json['last_run_at'] == null
      ? null
      : DateTime.parse(json['last_run_at'] as String),
  lastStatus: json['last_status'] as String?,
  reportId: json['report_id'] as String?,
  reportName: json['report_name'] as String?,
  weekday: (json['weekday'] as num?)?.toInt(),
);

Map<String, dynamic> _$ReportScheduleToJson(ReportSchedule instance) =>
    <String, dynamic>{
      'active': instance.active,
      'addresses': instance.addresses,
      'created_at': instance.createdAt.toIso8601String(),
      'day_of_month': ?instance.dayOfMonth,
      'format': instance.format,
      'frequency': instance.frequency,
      'helpdesk': ?instance.helpdesk,
      'id': instance.id,
      'last_error': ?instance.lastError,
      'last_run_at': ?instance.lastRunAt?.toIso8601String(),
      'last_status': ?instance.lastStatus,
      'name': instance.name,
      'next_run_at': instance.nextRunAt.toIso8601String(),
      'owner_id': instance.ownerId,
      'owner_name': instance.ownerName,
      'report_id': ?instance.reportId,
      'report_name': ?instance.reportName,
      'send_time': instance.sendTime,
      'source': instance.source,
      'time_zone': instance.timeZone,
      'updated_at': instance.updatedAt.toIso8601String(),
      'user_ids': instance.userIds,
      'weekday': ?instance.weekday,
    };
