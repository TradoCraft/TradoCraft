// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'model_summary.g.dart';

@JsonSerializable()
class ModelSummary {
  const ModelSummary({
    required this.active,
    required this.code,
    required this.description,
    required this.id,
    required this.name,
    required this.updatedAt,
    this.activeRevision,
    this.activeRevisionId,
    this.draftRevision,
    this.draftRevisionId,
    this.productId,
  });
  
  factory ModelSummary.fromJson(Map<String, Object?> json) => _$ModelSummaryFromJson(json);
  
  final bool active;

  /// Revision number of the active revision, if any.
  @JsonKey(includeIfNull: false,name: 'active_revision')
  final int? activeRevision;
  @JsonKey(includeIfNull: false,name: 'active_revision_id')
  final String? activeRevisionId;
  final String code;
  final String description;

  /// Revision number of the draft, if any.
  @JsonKey(includeIfNull: false,name: 'draft_revision')
  final int? draftRevision;
  @JsonKey(includeIfNull: false,name: 'draft_revision_id')
  final String? draftRevisionId;
  final String id;
  final String name;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ModelSummaryToJson(this);
}
