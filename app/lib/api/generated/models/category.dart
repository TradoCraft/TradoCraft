// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'category_name.dart';

part 'category.g.dart';

@JsonSerializable()
class Category {
  const Category({
    required this.active,
    required this.entryCount,
    required this.id,
    required this.names,
    required this.sortOrder,
    this.parentId,
  });
  
  factory Category.fromJson(Map<String, Object?> json) => _$CategoryFromJson(json);
  
  final bool active;

  /// Entries in this category (not counting its sub-categories).
  @JsonKey(name: 'entry_count')
  final int entryCount;
  final String id;
  final List<CategoryName> names;

  /// Only one level of nesting: the parent has no parent itself.
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$CategoryToJson(this);
}
