// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reorder_input.g.dart';

@JsonSerializable()
class ReorderInput {
  const ReorderInput({
    required this.ids,
    this.parentId,
  });
  
  factory ReorderInput.fromJson(Map<String, Object?> json) => _$ReorderInputFromJson(json);
  
  /// The items in their new order. They take the positions the same items had, so items that are.
  /// not in the list (for example finished ones that are hidden) keep their places.
  final List<String> ids;

  /// The common parent; absent for root items.
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;

  Map<String, Object?> toJson() => _$ReorderInputToJson(this);
}
