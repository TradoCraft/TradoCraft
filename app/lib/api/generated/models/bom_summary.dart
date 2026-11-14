// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'bom_summary.g.dart';

@JsonSerializable()
class BomSummary {
  const BomSummary({
    required this.createdAt,
    required this.id,
    required this.lineCount,
    required this.notes,
    required this.productId,
    required this.revision,
    required this.status,
    this.activatedAt,
  });
  
  factory BomSummary.fromJson(Map<String, Object?> json) => _$BomSummaryFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'activated_at')
  final DateTime? activatedAt;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  @JsonKey(name: 'line_count')
  final int lineCount;
  final String notes;
  @JsonKey(name: 'product_id')
  final String productId;
  final int revision;

  /// draft | active | obsolete
  final String status;

  Map<String, Object?> toJson() => _$BomSummaryToJson(this);
}
