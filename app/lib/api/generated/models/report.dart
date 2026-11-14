// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'count_row.dart';
import 'csat_stats.dart';
import 'duration_stats.dart';
import 'sla_stats.dart';
import 'team_breaches.dart';
import 'time_row.dart';
import 'volume_point.dart';

part 'report.g.dart';

@JsonSerializable()
class Report {
  const Report({
    required this.backlogByOwner,
    required this.backlogByPriority,
    required this.backlogByStatus,
    required this.backlogByTeam,
    required this.basis,
    required this.breachesByTeam,
    required this.csat,
    required this.firstResponse,
    required this.from,
    required this.group,
    required this.resolution,
    required this.sla,
    required this.timeBillableMinutes,
    required this.timeByUser,
    required this.timeNonBillableMinutes,
    required this.to,
    required this.topCategories,
    required this.topTags,
    required this.volume,
  });
  
  factory Report.fromJson(Map<String, Object?> json) => _$ReportFromJson(json);
  
  @JsonKey(name: 'backlog_by_owner')
  final List<CountRow> backlogByOwner;
  @JsonKey(name: 'backlog_by_priority')
  final List<CountRow> backlogByPriority;
  @JsonKey(name: 'backlog_by_status')
  final List<CountRow> backlogByStatus;
  @JsonKey(name: 'backlog_by_team')
  final List<CountRow> backlogByTeam;

  /// How response and resolution times are measured: `business` (every ticket's calendar is.
  /// on), `elapsed`, or `mixed` (some teams have a calendar and others do not).
  final String basis;
  @JsonKey(name: 'breaches_by_team')
  final List<TeamBreaches> breachesByTeam;
  final CsatStats csat;
  @JsonKey(name: 'first_response')
  final DurationStats firstResponse;
  final DateTime from;

  /// day | week
  final String group;
  final DurationStats resolution;
  final SlaStats sla;
  @JsonKey(name: 'time_billable_minutes')
  final int timeBillableMinutes;
  @JsonKey(name: 'time_by_user')
  final List<TimeRow> timeByUser;
  @JsonKey(name: 'time_non_billable_minutes')
  final int timeNonBillableMinutes;
  final DateTime to;
  @JsonKey(name: 'top_categories')
  final List<CountRow> topCategories;
  @JsonKey(name: 'top_tags')
  final List<CountRow> topTags;
  final List<VolumePoint> volume;

  Map<String, Object?> toJson() => _$ReportToJson(this);
}
