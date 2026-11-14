// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_chart.dart';
import 'report_run_column.dart';

part 'report_run_result.g.dart';

/// The result of running a report.
@JsonSerializable()
class ReportRunResult {
  const ReportRunResult({
    required this.asOf,
    required this.columns,
    required this.rows,
    required this.total,
    this.chart,
    this.totals,
  });
  
  factory ReportRunResult.fromJson(Map<String, Object?> json) => _$ReportRunResultFromJson(json);
  
  /// The date (`YYYY-MM-DD`) relative dates were resolved against. Send it back as `as_of`.
  /// when fetching further pages so every page comes from the same range, even across midnight.
  @JsonKey(name: 'as_of')
  final DateTime asOf;
  @JsonKey(includeIfNull: false)
  final ReportChart? chart;
  final List<ReportRunColumn> columns;

  /// One array per row, aligned with `columns`. Numbers are JSON numbers, dates `YYYY-MM-DD`.
  /// or ISO 8601 date-times, missing values null.
  final List<List<dynamic>> rows;

  /// Number of rows the report has, before paging.
  final int total;

  /// For grouped reports: the summaries over everything, aligned with `columns`.
  /// (null for grouping columns).
  @JsonKey(includeIfNull: false)
  final List<dynamic>? totals;

  Map<String, Object?> toJson() => _$ReportRunResultToJson(this);
}
