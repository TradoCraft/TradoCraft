// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'render_format.dart';

part 'export_plan_entry.g.dart';

/// One file to produce.
@JsonSerializable()
class ExportPlanEntry {
  const ExportPlanEntry({
    required this.format,
    required this.lang,
    required this.relativePath,
    required this.zoneCode,
    required this.zoneId,
    this.exportId,
  });
  
  factory ExportPlanEntry.fromJson(Map<String, Object?> json) => _$ExportPlanEntryFromJson(json);
  
  /// `null`: the whole list.
  @JsonKey(includeIfNull: false,name: 'export_id')
  final String? exportId;
  final RenderFormat format;
  final String lang;

  /// Forward-slash path, `<list>/<zone>/<lang>/<file>.<ext>`, every segment sanitized and the.
  /// whole path unique (ignoring case) within the plan.
  @JsonKey(name: 'relative_path')
  final String relativePath;
  @JsonKey(name: 'zone_code')
  final String zoneCode;
  @JsonKey(name: 'zone_id')
  final String zoneId;

  Map<String, Object?> toJson() => _$ExportPlanEntryToJson(this);
}
