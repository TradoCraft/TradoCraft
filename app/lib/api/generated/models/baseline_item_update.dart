// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'baseline_item_update.g.dart';

/// Replaces an item: what is not sent falls back to its default (no parent, no name, quantity 1,.
/// no values); only `sort_order` keeps its stored value when omitted. The type cannot change.
@JsonSerializable()
class BaselineItemUpdate {
  const BaselineItemUpdate({
    this.name,
    this.parentId,
    this.quantity,
    this.sortOrder,
    this.values,
  });
  
  factory BaselineItemUpdate.fromJson(Map<String, Object?> json) => _$BaselineItemUpdateFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? name;

  /// Omit (null) to move the item to the top level.
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;
  @JsonKey(includeIfNull: false)
  final int? quantity;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;
  @JsonKey(includeIfNull: false)
  final dynamic values;

  Map<String, Object?> toJson() => _$BaselineItemUpdateToJson(this);
}
