// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'exported_model.dart';

part 'model_export.g.dart';

/// A model with one revision's definition, as exported and imported (JSON file).
@JsonSerializable()
class ModelExport {
  const ModelExport({
    required this.definition,
    required this.format,
    required this.formatVersion,
    required this.model,
  });
  
  factory ModelExport.fromJson(Map<String, Object?> json) => _$ModelExportFromJson(json);
  
  final dynamic definition;

  /// Always `tradocraft.configurator`.
  final String format;
  @JsonKey(name: 'format_version')
  final int formatVersion;
  final ExportedModel model;

  Map<String, Object?> toJson() => _$ModelExportToJson(this);
}
