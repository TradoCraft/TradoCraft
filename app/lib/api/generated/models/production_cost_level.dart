// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_cost_level.g.dart';

/// One built product in the roll-up: the product itself and each subassembly below it.
@JsonSerializable()
class ProductionCostLevel {
  const ProductionCostLevel({
    required this.labourCost,
    required this.level,
    required this.materialCost,
    required this.minutes,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unit,
  });
  
  factory ProductionCostLevel.fromJson(Map<String, Object?> json) => _$ProductionCostLevelFromJson(json);
  
  /// Its own routing: operation minutes at the work centres' cost per hour.
  @JsonKey(name: 'labour_cost')
  final String labourCost;

  /// 0 for the product asked for, 1 for its subassemblies, and so on.
  final int level;

  /// Components that are bought, at their standard cost (subassemblies are costed on their own.
  /// level).
  @JsonKey(name: 'material_cost')
  final String materialCost;

  /// Minutes of its own routing for this quantity.
  final int minutes;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;

  /// How many of it are built.
  final String quantity;
  final String unit;

  Map<String, Object?> toJson() => _$ProductionCostLevelToJson(this);
}
