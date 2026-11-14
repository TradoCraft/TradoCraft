// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_chart.dart';
import 'report_column.dart';
import 'report_filter.dart';
import 'report_group_by.dart';
import 'report_logic.dart';
import 'report_sort.dart';

part 'report_definition.g.dart';

/// A stored report definition, as sent by clients.
@JsonSerializable()
class ReportDefinition {
  const ReportDefinition({
    required this.columns,
    required this.object,
    this.chart,
    this.filterLogic,
    this.filters,
    this.groupBy,
    this.joins,
    this.sort,
  });
  
  factory ReportDefinition.fromJson(Map<String, Object?> json) => _$ReportDefinitionFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final ReportChart? chart;
  final List<ReportColumn> columns;
  @JsonKey(includeIfNull: false,name: 'filter_logic')
  final ReportLogic? filterLogic;
  @JsonKey(includeIfNull: false)
  final List<ReportFilter>? filters;
  @JsonKey(includeIfNull: false,name: 'group_by')
  final List<ReportGroupBy>? groupBy;

  /// Further objects to bring in, each related to one already in the report.
  @JsonKey(includeIfNull: false)
  final List<String>? joins;

  /// The object the report is about: `customer`, `quotation` or `order`.
  final String object;
  @JsonKey(includeIfNull: false)
  final List<ReportSort>? sort;

  Map<String, Object?> toJson() => _$ReportDefinitionToJson(this);
}
