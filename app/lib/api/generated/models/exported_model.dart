// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'exported_model.g.dart';

/// The model part of an export.
@JsonSerializable()
class ExportedModel {
  const ExportedModel({
    required this.code,
    required this.name,
    this.description,
    this.translations,
  });
  
  factory ExportedModel.fromJson(Map<String, Object?> json) => _$ExportedModelFromJson(json);
  
  final String code;
  @JsonKey(includeIfNull: false)
  final String? description;
  final String name;
  @JsonKey(includeIfNull: false)
  final dynamic translations;

  Map<String, Object?> toJson() => _$ExportedModelToJson(this);
}
