// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'reader_image.dart';
import 'reader_link.dart';

part 'reader_entry.g.dart';

@JsonSerializable()
class ReaderEntry {
  const ReaderEntry({
    required this.availableLanguages,
    required this.body,
    required this.fallback,
    required this.id,
    required this.images,
    required this.language,
    required this.number,
    required this.related,
    required this.slug,
    required this.summary,
    required this.tags,
    required this.title,
    required this.updatedAt,
    this.categoryId,
    this.myVote,
  });
  
  factory ReaderEntry.fromJson(Map<String, Object?> json) => _$ReaderEntryFromJson(json);
  
  @JsonKey(name: 'available_languages')
  final List<String> availableLanguages;

  /// Simple Markdown. Images are written as `image:<id>` and listed in `images`.
  final String body;
  @JsonKey(includeIfNull: false,name: 'category_id')
  final String? categoryId;

  /// True when the text is not in the language asked for.
  final bool fallback;
  final String id;
  final List<ReaderImage> images;

  /// The language of the text shown.
  final String language;

  /// The vote of the logged-in contact (portal only): true = helpful.
  @JsonKey(includeIfNull: false,name: 'my_vote')
  final bool? myVote;
  final String number;
  final List<ReaderLink> related;
  final String slug;
  final String summary;
  final List<String> tags;
  final String title;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ReaderEntryToJson(this);
}
