// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'entry_text.dart';

part 'entry_input.g.dart';

@JsonSerializable()
class EntryInput {
  const EntryInput({
    required this.texts,
    required this.visibility,
    this.categoryId,
    this.productIds,
    this.relatedIds,
    this.tags,
    this.ticketCategories,
  });
  
  factory EntryInput.fromJson(Map<String, Object?> json) => _$EntryInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'category_id')
  final String? categoryId;
  @JsonKey(includeIfNull: false,name: 'product_ids')
  final List<String>? productIds;
  @JsonKey(includeIfNull: false,name: 'related_ids')
  final List<String>? relatedIds;
  @JsonKey(includeIfNull: false)
  final List<String>? tags;

  /// At least one language with a title; others fall back to English.
  final List<EntryText> texts;
  @JsonKey(includeIfNull: false,name: 'ticket_categories')
  final List<String>? ticketCategories;

  /// internal | portal | public
  final String visibility;

  Map<String, Object?> toJson() => _$EntryInputToJson(this);
}
