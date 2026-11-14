// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_column_kind.dart';
import 'report_field_type.dart';

part 'report_run_column.g.dart';

/// A column of a run result.
@JsonSerializable()
class ReportRunColumn {
  const ReportRunColumn({
    required this.key,
    required this.kind,
    required this.label,
    required this.type,
  });
  
  factory ReportRunColumn.fromJson(Map<String, Object?> json) => _$ReportRunColumnFromJson(json);
  
  /// Key to use in `sort` and `chart`.
  final String key;
  final ReportColumnKind kind;
  final String label;
  final ReportFieldType type;

  Map<String, Object?> toJson() => _$ReportRunColumnToJson(this);
}
