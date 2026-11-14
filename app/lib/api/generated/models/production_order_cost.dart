// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_order_cost.g.dart';

/// Cost of a production order, in the company currency.
@JsonSerializable()
class ProductionOrderCost {
  const ProductionOrderCost({
    required this.incomplete,
    required this.labourCost,
    required this.materialCost,
    required this.totalCost,
  });
  
  factory ProductionOrderCost.fromJson(Map<String, Object?> json) => _$ProductionOrderCostFromJson(json);
  
  /// A component had no standard cost or an operation no rate: its cost is left out.
  final bool incomplete;

  /// Operation minutes at the cost per hour the operations had.
  @JsonKey(name: 'labour_cost')
  final String labourCost;

  /// Components at the standard cost they had when the order was released.
  @JsonKey(name: 'material_cost')
  final String materialCost;
  @JsonKey(name: 'total_cost')
  final String totalCost;

  Map<String, Object?> toJson() => _$ProductionOrderCostToJson(this);
}
