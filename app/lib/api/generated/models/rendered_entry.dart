// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rendered_entry.g.dart';

@JsonSerializable()
class RenderedEntry {
  const RenderedEntry({
    required this.entryId,
    required this.fallback,
    required this.language,
    required this.summary,
    required this.text,
    required this.title,
    this.link,
  });
  
  factory RenderedEntry.fromJson(Map<String, Object?> json) => _$RenderedEntryFromJson(json);
  
  @JsonKey(name: 'entry_id')
  final String entryId;

  /// True when the ticket's language has no text and another was used.
  final bool fallback;

  /// Language of the text used.
  final String language;

  /// Address of the entry in the customer portal; absent for internal entries or when the.
  /// company has no portal address.
  @JsonKey(includeIfNull: false)
  final String? link;
  final String summary;

  /// The text without Markdown, ready for an e-mail.
  final String text;
  final String title;

  Map<String, Object?> toJson() => _$RenderedEntryToJson(this);
}
