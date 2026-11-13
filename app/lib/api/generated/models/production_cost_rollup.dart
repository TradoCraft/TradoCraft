// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_cost_gap.dart';
import 'production_cost_level.dart';

part 'production_cost_rollup.g.dart';

@JsonSerializable()
class ProductionCostRollup {
  const ProductionCostRollup({
    required this.currency,
    required this.gaps,
    required this.labourCost,
    required this.levels,
    required this.materialCost,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.totalCost,
    required this.unit,
    required this.unitCost,
  });
  
  factory ProductionCostRollup.fromJson(Map<String, Object?> json) => _$ProductionCostRollupFromJson(json);
  
  /// The company currency.
  final String currency;

  /// What was left out because it has no cost.
  final List<ProductionCostGap> gaps;
  @JsonKey(name: 'labour_cost')
  final String labourCost;

  /// The product and each subassembly, in the order they are met.
  final List<ProductionCostLevel> levels;
  @JsonKey(name: 'material_cost')
  final String materialCost;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  final String quantity;
  @JsonKey(name: 'total_cost')
  final String totalCost;
  final String unit;

  /// Total cost for one unit of the product.
  @JsonKey(name: 'unit_cost')
  final String unitCost;

  Map<String, Object?> toJson() => _$ProductionCostRollupToJson(this);
}
