// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'entry_text.g.dart';

@JsonSerializable()
class EntryText {
  const EntryText({
    required this.language,
    required this.title,
    this.body,
    this.summary,
  });
  
  factory EntryText.fromJson(Map<String, Object?> json) => _$EntryTextFromJson(json);
  
  /// Simple Markdown: headings, bold, italics, lists, links and images (`image:<file id>`).
  @JsonKey(includeIfNull: false)
  final String? body;

  /// nl | fr | en | de | es
  final String language;
  @JsonKey(includeIfNull: false)
  final String? summary;
  final String title;

  Map<String, Object?> toJson() => _$EntryTextToJson(this);
}
