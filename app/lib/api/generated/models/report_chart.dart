// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_chart_kind.dart';

part 'report_chart.g.dart';

/// The chart of a report: kind, x column and y column.
@JsonSerializable()
class ReportChart {
  const ReportChart({
    required this.kind,
    required this.x,
    required this.y,
  });
  
  factory ReportChart.fromJson(Map<String, Object?> json) => _$ReportChartFromJson(json);
  
  final ReportChartKind kind;

  /// Key of a grouping column.
  final String x;

  /// Key of a numeric summary column.
  final String y;

  Map<String, Object?> toJson() => _$ReportChartToJson(this);
}
