// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reader_summary.g.dart';

/// Public summary of a hit: nothing about counters or status.
@JsonSerializable()
class ReaderSummary {
  const ReaderSummary({
    required this.fallback,
    required this.id,
    required this.language,
    required this.number,
    required this.slug,
    required this.snippet,
    required this.tags,
    required this.title,
    required this.updatedAt,
    this.categoryId,
  });
  
  factory ReaderSummary.fromJson(Map<String, Object?> json) => _$ReaderSummaryFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'category_id')
  final String? categoryId;
  final bool fallback;
  final String id;
  final String language;
  final String number;
  final String slug;

  /// Plain text; matched words are wrapped in U+E000 / U+E001 when searching.
  final String snippet;
  final List<String> tags;
  final String title;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ReaderSummaryToJson(this);
}
