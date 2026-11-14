// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'entry_text.dart';
import 'file_info.dart';
import 'related_entry.dart';

part 'entry.g.dart';

@JsonSerializable()
class Entry {
  const Entry({
    required this.createdAt,
    required this.helpfulNo,
    required this.helpfulYes,
    required this.id,
    required this.images,
    required this.number,
    required this.productIds,
    required this.related,
    required this.slug,
    required this.status,
    required this.tags,
    required this.texts,
    required this.ticketCategories,
    required this.updatedAt,
    required this.version,
    required this.viewCount,
    required this.visibility,
    this.authorId,
    this.authorName,
    this.categoryId,
    this.publishedAt,
  });
  
  factory Entry.fromJson(Map<String, Object?> json) => _$EntryFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'author_id')
  final String? authorId;
  @JsonKey(includeIfNull: false,name: 'author_name')
  final String? authorName;
  @JsonKey(includeIfNull: false,name: 'category_id')
  final String? categoryId;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'helpful_no')
  final int helpfulNo;
  @JsonKey(name: 'helpful_yes')
  final int helpfulYes;
  final String id;
  final List<FileInfo> images;
  final String number;
  @JsonKey(name: 'product_ids')
  final List<String> productIds;
  @JsonKey(includeIfNull: false,name: 'published_at')
  final DateTime? publishedAt;
  final List<RelatedEntry> related;
  final String slug;

  /// draft | published | archived
  final String status;
  final List<String> tags;
  final List<EntryText> texts;

  /// Ticket categories this entry helps with (shown first in suggestions).
  @JsonKey(name: 'ticket_categories')
  final List<String> ticketCategories;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// Number of the latest saved version (0 when never published).
  final int version;
  @JsonKey(name: 'view_count')
  final int viewCount;

  /// internal | portal | public
  final String visibility;

  Map<String, Object?> toJson() => _$EntryToJson(this);
}
