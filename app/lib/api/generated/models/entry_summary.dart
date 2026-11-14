// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'entry_summary.g.dart';

@JsonSerializable()
class EntrySummary {
  const EntrySummary({
    required this.fallback,
    required this.helpfulNo,
    required this.helpfulYes,
    required this.id,
    required this.language,
    required this.number,
    required this.slug,
    required this.snippet,
    required this.status,
    required this.tags,
    required this.title,
    required this.updatedAt,
    required this.viewCount,
    required this.visibility,
    this.categoryId,
    this.publishedAt,
    this.score,
  });
  
  factory EntrySummary.fromJson(Map<String, Object?> json) => _$EntrySummaryFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'category_id')
  final String? categoryId;
  final bool fallback;
  @JsonKey(name: 'helpful_no')
  final int helpfulNo;
  @JsonKey(name: 'helpful_yes')
  final int helpfulYes;
  final String id;

  /// The language of the title and snippet shown.
  final String language;
  final String number;
  @JsonKey(includeIfNull: false,name: 'published_at')
  final DateTime? publishedAt;

  /// Relevance of a search match (higher is better).
  @JsonKey(includeIfNull: false)
  final double? score;
  final String slug;

  /// Plain text; matched words are wrapped in U+E000 / U+E001 when searching.
  final String snippet;
  final String status;
  final List<String> tags;
  final String title;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
  @JsonKey(name: 'view_count')
  final int viewCount;
  final String visibility;

  Map<String, Object?> toJson() => _$EntrySummaryToJson(this);
}
