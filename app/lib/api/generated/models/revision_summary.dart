// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'revision_summary.g.dart';

@JsonSerializable()
class RevisionSummary {
  const RevisionSummary({
    required this.createdAt,
    required this.id,
    required this.modelId,
    required this.notes,
    required this.revision,
    required this.status,
    this.activatedAt,
  });
  
  factory RevisionSummary.fromJson(Map<String, Object?> json) => _$RevisionSummaryFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'activated_at')
  final DateTime? activatedAt;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  @JsonKey(name: 'model_id')
  final String modelId;
  final String notes;
  final int revision;

  /// draft | active | obsolete
  final String status;

  Map<String, Object?> toJson() => _$RevisionSummaryToJson(this);
}
