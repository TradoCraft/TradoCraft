// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_order_cost.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionOrderCost _$ProductionOrderCostFromJson(Map<String, dynamic> json) =>
    ProductionOrderCost(
      incomplete: json['incomplete'] as bool,
      labourCost: json['labour_cost'] as String,
      materialCost: json['material_cost'] as String,
      totalCost: json['total_cost'] as String,
    );

Map<String, dynamic> _$ProductionOrderCostToJson(
  ProductionOrderCost instance,
) => <String, dynamic>{
  'incomplete': instance.incomplete,
  'labour_cost': instance.labourCost,
  'material_cost': instance.materialCost,
  'total_cost': instance.totalCost,
};
