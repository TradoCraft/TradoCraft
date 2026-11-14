// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'helpdesk_report_spec.g.dart';

/// Which helpdesk table to mail and for which period.
@JsonSerializable()
class HelpdeskReportSpec {
  const HelpdeskReportSpec({
    required this.period,
    required this.table,
    this.category,
    this.group,
    this.ownerId,
    this.teamId,
  });

  factory HelpdeskReportSpec.fromJson(Map<String, Object?> json) =>
      _$HelpdeskReportSpecFromJson(json);

  @JsonKey(includeIfNull: false)
  final String? category;

  /// `day` (default) or `week`.
  @JsonKey(includeIfNull: false)
  final String? group;
  @JsonKey(includeIfNull: false, name: 'owner_id')
  final String? ownerId;

  /// yesterday | last_7_days | last_week (Monday to Sunday before today) | last_30_days |.
  /// last_month (the calendar month before this one), counted in the schedule's time zone.
  final String period;

  /// One of the tables of `GET /helpdesk/reports/export` (volume, backlog_status, times, sla, ...).
  final String table;
  @JsonKey(includeIfNull: false, name: 'team_id')
  final String? teamId;

  Map<String, Object?> toJson() => _$HelpdeskReportSpecToJson(this);
}
