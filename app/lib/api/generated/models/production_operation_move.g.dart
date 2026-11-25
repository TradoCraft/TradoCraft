// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_operation_move.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionOperationMove _$ProductionOperationMoveFromJson(
  Map<String, dynamic> json,
) => ProductionOperationMove(
  applied: json['applied'] as bool,
  conflicts: (json['conflicts'] as List<dynamic>)
      .map((e) => ProductionMoveConflict.fromJson(e as Map<String, dynamic>))
      .toList(),
  order: json['order'] == null
      ? null
      : ProductionOrder.fromJson(json['order'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ProductionOperationMoveToJson(
  ProductionOperationMove instance,
) => <String, dynamic>{
  'applied': instance.applied,
  'conflicts': instance.conflicts,
  'order': ?instance.order,
};
