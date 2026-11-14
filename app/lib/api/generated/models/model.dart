// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'revision_summary.dart';

part 'model.g.dart';

@JsonSerializable()
class Model {
  const Model({
    required this.active,
    required this.code,
    required this.createdAt,
    required this.description,
    required this.id,
    required this.name,
    required this.revisions,
    required this.translations,
    required this.updatedAt,
    this.productId,
  });
  
  factory Model.fromJson(Map<String, Object?> json) => _$ModelFromJson(json);
  
  final bool active;
  final String code;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String description;
  final String id;
  final String name;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// Newest first.
  final List<RevisionSummary> revisions;

  /// Names per language: `{"nl": {"label": "..."}}`.
  final dynamic translations;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ModelToJson(this);
}
