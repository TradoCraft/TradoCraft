// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'explosion_node.g.dart';

/// One row of an exploded structure, depth-first. `parent_index` points into the same list.
@JsonSerializable()
class ExplosionNode {
  const ExplosionNode({
    required this.code,
    required this.isLeaf,
    required this.level,
    required this.name,
    required this.productId,
    required this.productType,
    required this.quantityPerParent,
    required this.requiredQuantity,
    required this.scrapPercent,
    required this.unit,
    this.parentIndex,
  });
  
  factory ExplosionNode.fromJson(Map<String, Object?> json) => _$ExplosionNodeFromJson(json);
  
  final String code;
  @JsonKey(name: 'is_leaf')
  final bool isLeaf;
  final int level;
  final String name;
  @JsonKey(includeIfNull: false,name: 'parent_index')
  final int? parentIndex;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_type')
  final String productType;
  @JsonKey(name: 'quantity_per_parent')
  final String quantityPerParent;

  /// Needed for the requested quantity, scrap included (rounded to 4 decimals).
  @JsonKey(name: 'required_quantity')
  final String requiredQuantity;
  @JsonKey(name: 'scrap_percent')
  final String scrapPercent;
  final String unit;

  Map<String, Object?> toJson() => _$ExplosionNodeToJson(this);
}
