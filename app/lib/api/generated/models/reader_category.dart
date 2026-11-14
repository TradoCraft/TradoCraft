// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reader_category.g.dart';

@JsonSerializable()
class ReaderCategory {
  const ReaderCategory({
    required this.entryCount,
    required this.id,
    required this.name,
    required this.sortOrder,
    this.parentId,
  });
  
  factory ReaderCategory.fromJson(Map<String, Object?> json) => _$ReaderCategoryFromJson(json);
  
  /// Entries the reader can open in this category, sub-categories included.
  @JsonKey(name: 'entry_count')
  final int entryCount;
  final String id;
  final String name;
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$ReaderCategoryToJson(this);
}
