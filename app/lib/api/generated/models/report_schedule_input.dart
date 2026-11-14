// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'helpdesk_report_spec.dart';

part 'report_schedule_input.g.dart';

@JsonSerializable()
class ReportScheduleInput {
  const ReportScheduleInput({
    required this.format,
    required this.frequency,
    required this.name,
    required this.source,
    this.active,
    this.addresses,
    this.dayOfMonth,
    this.helpdesk,
    this.reportId,
    this.sendTime,
    this.timeZone,
    this.userIds,
    this.weekday,
  });

  factory ReportScheduleInput.fromJson(Map<String, Object?> json) =>
      _$ReportScheduleInputFromJson(json);

  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false)
  final List<String>? addresses;
  @JsonKey(includeIfNull: false, name: 'day_of_month')
  final int? dayOfMonth;
  final String format;
  final String frequency;

  /// For `helpdesk`.
  @JsonKey(includeIfNull: false)
  final HelpdeskReportSpec? helpdesk;
  final String name;

  /// For `custom`.
  @JsonKey(includeIfNull: false, name: 'report_id')
  final String? reportId;

  /// Local time, `HH:MM`. Default 07:00.
  @JsonKey(includeIfNull: false, name: 'send_time')
  final String? sendTime;
  final String source;

  /// An IANA zone, default `Europe/Brussels`.
  @JsonKey(includeIfNull: false, name: 'time_zone')
  final String? timeZone;
  @JsonKey(includeIfNull: false, name: 'user_ids')
  final List<String>? userIds;
  @JsonKey(includeIfNull: false)
  final int? weekday;

  Map<String, Object?> toJson() => _$ReportScheduleInputToJson(this);
}
