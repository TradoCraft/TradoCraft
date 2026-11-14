// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'definition_error.dart';

part 'revision.g.dart';

@JsonSerializable()
class Revision {
  const Revision({
    required this.createdAt,
    required this.definition,
    required this.errors,
    required this.id,
    required this.modelCode,
    required this.modelId,
    required this.modelName,
    required this.notes,
    required this.revision,
    required this.status,
    required this.updatedAt,
    this.activatedAt,
  });
  
  factory Revision.fromJson(Map<String, Object?> json) => _$RevisionFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'activated_at')
  final DateTime? activatedAt;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// The definition document (ADR 0034).
  final dynamic definition;

  /// Problems that block activation; empty when the definition is valid.
  final List<DefinitionError> errors;
  final String id;
  @JsonKey(name: 'model_code')
  final String modelCode;
  @JsonKey(name: 'model_id')
  final String modelId;
  @JsonKey(name: 'model_name')
  final String modelName;
  final String notes;
  final int revision;

  /// draft | active | obsolete
  final String status;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$RevisionToJson(this);
}
