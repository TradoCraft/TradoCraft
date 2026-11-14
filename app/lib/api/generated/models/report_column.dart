// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_summary.dart';

part 'report_column.g.dart';

/// A column of a report: a field, optionally summarised, with an optional label.
@JsonSerializable()
class ReportColumn {
  const ReportColumn({
    required this.field,
    this.label,
    this.summary,
  });
  
  factory ReportColumn.fromJson(Map<String, Object?> json) => _$ReportColumnFromJson(json);
  
  /// `object.field`, e.g. `quotation.total`.
  final String field;

  /// Heading; default is derived from the field.
  @JsonKey(includeIfNull: false)
  final String? label;

  /// Turns the column into a summary; needs a grouping or makes the report a single row.
  @JsonKey(includeIfNull: false)
  final ReportSummary? summary;

  Map<String, Object?> toJson() => _$ReportColumnToJson(this);
}
