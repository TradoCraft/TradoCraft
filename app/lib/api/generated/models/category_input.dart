// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'category_name.dart';

part 'category_input.g.dart';

@JsonSerializable()
class CategoryInput {
  const CategoryInput({
    required this.names,
    this.active,
    this.parentId,
    this.sortOrder,
  });
  
  factory CategoryInput.fromJson(Map<String, Object?> json) => _$CategoryInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;

  /// At least one language; the others fall back to English.
  final List<CategoryName> names;
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$CategoryInputToJson(this);
}
