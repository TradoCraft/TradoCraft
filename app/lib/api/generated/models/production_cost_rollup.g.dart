// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_cost_rollup.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionCostRollup _$ProductionCostRollupFromJson(
  Map<String, dynamic> json,
) => ProductionCostRollup(
  currency: json['currency'] as String,
  gaps: (json['gaps'] as List<dynamic>)
      .map((e) => ProductionCostGap.fromJson(e as Map<String, dynamic>))
      .toList(),
  labourCost: json['labour_cost'] as String,
  levels: (json['levels'] as List<dynamic>)
      .map((e) => ProductionCostLevel.fromJson(e as Map<String, dynamic>))
      .toList(),
  materialCost: json['material_cost'] as String,
  productCode: json['product_code'] as String,
  productId: json['product_id'] as String,
  productName: json['product_name'] as String,
  quantity: json['quantity'] as String,
  totalCost: json['total_cost'] as String,
  unit: json['unit'] as String,
  unitCost: json['unit_cost'] as String,
);

Map<String, dynamic> _$ProductionCostRollupToJson(
  ProductionCostRollup instance,
) => <String, dynamic>{
  'currency': instance.currency,
  'gaps': instance.gaps,
  'labour_cost': instance.labourCost,
  'levels': instance.levels,
  'material_cost': instance.materialCost,
  'product_code': instance.productCode,
  'product_id': instance.productId,
  'product_name': instance.productName,
  'quantity': instance.quantity,
  'total_cost': instance.totalCost,
  'unit': instance.unit,
  'unit_cost': instance.unitCost,
};
