// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'import_counts.dart';
import 'import_preview_item.dart';
import 'import_warning.dart';
import 'unmapped_field.dart';

part 'baseline_import_report.g.dart';

@JsonSerializable()
class BaselineImportReport {
  const BaselineImportReport({
    required this.created,
    required this.dryRun,
    required this.items,
    required this.replaced,
    required this.sourceId,
    required this.unmappedFields,
    required this.warnings,
  });
  
  factory BaselineImportReport.fromJson(Map<String, Object?> json) => _$BaselineImportReportFromJson(json);
  
  final ImportCounts created;
  @JsonKey(name: 'dry_run')
  final bool dryRun;

  /// The group first, then its bells.
  final List<ImportPreviewItem> items;

  /// Items of the same source that are (dry run) or were replaced.
  final int replaced;
  @JsonKey(name: 'source_id')
  final String sourceId;
  @JsonKey(name: 'unmapped_fields')
  final List<UnmappedField> unmappedFields;
  final List<ImportWarning> warnings;

  Map<String, Object?> toJson() => _$BaselineImportReportToJson(this);
}
