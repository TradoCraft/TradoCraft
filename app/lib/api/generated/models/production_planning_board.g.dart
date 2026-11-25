// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_planning_board.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionPlanningBoard _$ProductionPlanningBoardFromJson(
  Map<String, dynamic> json,
) => ProductionPlanningBoard(
  centres: (json['centres'] as List<dynamic>)
      .map((e) => ProductionCapacityCentre.fromJson(e as Map<String, dynamic>))
      .toList(),
  from: DateTime.parse(json['from'] as String),
  operations: (json['operations'] as List<dynamic>)
      .map((e) => ProductionBoardOperation.fromJson(e as Map<String, dynamic>))
      .toList(),
  to: DateTime.parse(json['to'] as String),
);

Map<String, dynamic> _$ProductionPlanningBoardToJson(
  ProductionPlanningBoard instance,
) => <String, dynamic>{
  'centres': instance.centres,
  'from': instance.from.toIso8601String(),
  'operations': instance.operations,
  'to': instance.to.toIso8601String(),
};
