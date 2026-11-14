// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'favorite_item_input.dart';

part 'favorite_input.g.dart';

@JsonSerializable()
class FavoriteInput {
  const FavoriteInput({
    required this.items,
    required this.name,
  });
  
  factory FavoriteInput.fromJson(Map<String, Object?> json) => _$FavoriteInputFromJson(json);
  
  /// The main item first, then its option lines; 1 to 40 items.
  final List<FavoriteItemInput> items;

  /// Unique in the company, ignoring case; at most 120 characters.
  final String name;

  Map<String, Object?> toJson() => _$FavoriteInputToJson(this);
}
