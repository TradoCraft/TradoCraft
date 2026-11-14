// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'row_error.dart';

part 'import_report.g.dart';

/// Outcome of an import (or of its dry run). `errors` is empty on success; with errors nothing was.
/// written and the counts are 0.
@JsonSerializable()
class ImportReport {
  const ImportReport({
    required this.created,
    required this.errors,
    required this.unchanged,
    required this.updated,
  });
  
  factory ImportReport.fromJson(Map<String, Object?> json) => _$ImportReportFromJson(json);
  
  final int created;
  final List<RowError> errors;
  final int unchanged;
  final int updated;

  Map<String, Object?> toJson() => _$ImportReportToJson(this);
}
