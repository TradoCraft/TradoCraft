// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'favorite_item.dart';

part 'favorite.g.dart';

/// A favorite with its items.
@JsonSerializable()
class Favorite {
  const Favorite({
    required this.createdAt,
    required this.createdBy,
    required this.id,
    required this.items,
    required this.name,
    required this.updatedAt,
  });

  factory Favorite.fromJson(Map<String, Object?> json) =>
      _$FavoriteFromJson(json);

  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'created_by')
  final String createdBy;
  final String id;

  /// In loading order; the first item is the main item.
  final List<FavoriteItem> items;
  final String name;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$FavoriteToJson(this);
}
