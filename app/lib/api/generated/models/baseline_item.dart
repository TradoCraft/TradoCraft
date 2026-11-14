// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'baseline_item.dart';

part 'baseline_item.g.dart';

/// One baseline item. `children` is only filled in the tree returned by `GET .../baseline`.
@JsonSerializable()
class BaselineItem {
  const BaselineItem({
    required this.children,
    required this.createdAt,
    required this.id,
    required this.quantity,
    required this.sortOrder,
    required this.typeCode,
    required this.updatedAt,
    required this.values,
    this.name,
    this.parentId,
  });
  
  factory BaselineItem.fromJson(Map<String, Object?> json) => _$BaselineItemFromJson(json);
  
  final List<BaselineItem> children;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  @JsonKey(includeIfNull: false)
  final String? name;
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;
  final int quantity;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @JsonKey(name: 'type_code')
  final String typeCode;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// Attribute values keyed by attribute definition key.
  final dynamic values;

  Map<String, Object?> toJson() => _$BaselineItemToJson(this);
}
