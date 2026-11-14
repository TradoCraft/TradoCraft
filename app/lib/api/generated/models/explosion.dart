// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'explosion_node.dart';
import 'requirement.dart';

part 'explosion.g.dart';

@JsonSerializable()
class Explosion {
  const Explosion({
    required this.bomRevision,
    required this.nodes,
    required this.productId,
    required this.quantity,
    required this.requirements,
  });
  
  factory Explosion.fromJson(Map<String, Object?> json) => _$ExplosionFromJson(json);
  
  @JsonKey(name: 'bom_revision')
  final int bomRevision;
  final List<ExplosionNode> nodes;
  @JsonKey(name: 'product_id')
  final String productId;
  final String quantity;

  /// Totals of leaf components (to buy, or to make without a BOM).
  final List<Requirement> requirements;

  Map<String, Object?> toJson() => _$ExplosionToJson(this);
}
