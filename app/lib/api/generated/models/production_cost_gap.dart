// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_cost_gap.g.dart';

/// Something that could not be costed and was left out.
@JsonSerializable()
class ProductionCostGap {
  const ProductionCostGap({
    required this.code,
    required this.kind,
  });
  
  factory ProductionCostGap.fromJson(Map<String, Object?> json) => _$ProductionCostGapFromJson(json);
  
  /// The product or work centre code.
  final String code;

  /// standard_cost: a product without a standard cost; cost_per_hour: a work centre without one.
  final String kind;

  Map<String, Object?> toJson() => _$ProductionCostGapToJson(this);
}
