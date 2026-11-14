// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_cost_level.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionCostLevel _$ProductionCostLevelFromJson(Map<String, dynamic> json) =>
    ProductionCostLevel(
      labourCost: json['labour_cost'] as String,
      level: (json['level'] as num).toInt(),
      materialCost: json['material_cost'] as String,
      minutes: (json['minutes'] as num).toInt(),
      productCode: json['product_code'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      quantity: json['quantity'] as String,
      unit: json['unit'] as String,
    );

Map<String, dynamic> _$ProductionCostLevelToJson(
  ProductionCostLevel instance,
) => <String, dynamic>{
  'labour_cost': instance.labourCost,
  'level': instance.level,
  'material_cost': instance.materialCost,
  'minutes': instance.minutes,
  'product_code': instance.productCode,
  'product_id': instance.productId,
  'product_name': instance.productName,
  'quantity': instance.quantity,
  'unit': instance.unit,
};
