// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_definition.dart';

part 'saved_report_input.g.dart';

@JsonSerializable()
class SavedReportInput {
  const SavedReportInput({
    required this.definition,
    required this.name,
    this.description,
    this.shared,
  });
  
  factory SavedReportInput.fromJson(Map<String, Object?> json) => _$SavedReportInputFromJson(json);
  
  final ReportDefinition definition;
  @JsonKey(includeIfNull: false)
  final String? description;
  final String name;

  /// Share with everyone in the company who may run reports.
  @JsonKey(includeIfNull: false)
  final bool? shared;

  Map<String, Object?> toJson() => _$SavedReportInputToJson(this);
}
