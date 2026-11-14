// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_definition.dart';

part 'saved_report.g.dart';

@JsonSerializable()
class SavedReport {
  const SavedReport({
    required this.createdAt,
    required this.definition,
    required this.description,
    required this.id,
    required this.mine,
    required this.name,
    required this.object,
    required this.ownerId,
    required this.ownerName,
    required this.shared,
    required this.updatedAt,
  });
  
  factory SavedReport.fromJson(Map<String, Object?> json) => _$SavedReportFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final ReportDefinition definition;
  final String description;
  final String id;

  /// The caller owns the report.
  final bool mine;
  final String name;
  final String object;
  @JsonKey(name: 'owner_id')
  final String ownerId;
  @JsonKey(name: 'owner_name')
  final String ownerName;
  final bool shared;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$SavedReportToJson(this);
}
