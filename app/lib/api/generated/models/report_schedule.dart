// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'helpdesk_report_spec.dart';

part 'report_schedule.g.dart';

@JsonSerializable()
class ReportSchedule {
  const ReportSchedule({
    required this.active,
    required this.addresses,
    required this.createdAt,
    required this.format,
    required this.frequency,
    required this.id,
    required this.name,
    required this.nextRunAt,
    required this.ownerId,
    required this.ownerName,
    required this.sendTime,
    required this.source,
    required this.timeZone,
    required this.updatedAt,
    required this.userIds,
    this.dayOfMonth,
    this.helpdesk,
    this.lastError,
    this.lastRunAt,
    this.lastStatus,
    this.reportId,
    this.reportName,
    this.weekday,
  });
  
  factory ReportSchedule.fromJson(Map<String, Object?> json) => _$ReportScheduleFromJson(json);
  
  final bool active;

  /// Other recipients.
  final List<String> addresses;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// 1 to 28, for monthly.
  @JsonKey(includeIfNull: false,name: 'day_of_month')
  final int? dayOfMonth;

  /// csv | pdf
  final String format;

  /// daily | weekly | monthly
  final String frequency;
  @JsonKey(includeIfNull: false)
  final HelpdeskReportSpec? helpdesk;
  final String id;
  @JsonKey(includeIfNull: false,name: 'last_error')
  final String? lastError;
  @JsonKey(includeIfNull: false,name: 'last_run_at')
  final DateTime? lastRunAt;

  /// sent | failed
  @JsonKey(includeIfNull: false,name: 'last_status')
  final String? lastStatus;
  final String name;
  @JsonKey(name: 'next_run_at')
  final DateTime nextRunAt;
  @JsonKey(name: 'owner_id')
  final String ownerId;
  @JsonKey(name: 'owner_name')
  final String ownerName;
  @JsonKey(includeIfNull: false,name: 'report_id')
  final String? reportId;
  @JsonKey(includeIfNull: false,name: 'report_name')
  final String? reportName;

  /// Local time, `HH:MM`.
  @JsonKey(name: 'send_time')
  final String sendTime;

  /// `custom` (a saved report of the report builder) or `helpdesk` (a table of the helpdesk report).
  final String source;
  @JsonKey(name: 'time_zone')
  final String timeZone;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// Colleagues who receive it (active members of the company at the time it is sent).
  @JsonKey(name: 'user_ids')
  final List<String> userIds;

  /// 1 (Monday) to 7, for weekly.
  @JsonKey(includeIfNull: false)
  final int? weekday;

  Map<String, Object?> toJson() => _$ReportScheduleToJson(this);
}
