// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bom_routing.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BomRouting _$BomRoutingFromJson(Map<String, dynamic> json) => BomRouting(
  bomId: json['bom_id'] as String,
  bomRevision: (json['bom_revision'] as num).toInt(),
  bomStatus: json['bom_status'] as String,
  operations: (json['operations'] as List<dynamic>)
      .map((e) => RoutingOperation.fromJson(e as Map<String, dynamic>))
      .toList(),
  productId: json['product_id'] as String,
);

Map<String, dynamic> _$BomRoutingToJson(BomRouting instance) =>
    <String, dynamic>{
      'bom_id': instance.bomId,
      'bom_revision': instance.bomRevision,
      'bom_status': instance.bomStatus,
      'operations': instance.operations,
      'product_id': instance.productId,
    };
