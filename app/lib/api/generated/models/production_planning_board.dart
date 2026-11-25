// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_board_operation.dart';
import 'production_capacity_centre.dart';

part 'production_planning_board.g.dart';

@JsonSerializable()
class ProductionPlanningBoard {
  const ProductionPlanningBoard({
    required this.centres,
    required this.from,
    required this.operations,
    required this.to,
  });
  
  factory ProductionPlanningBoard.fromJson(Map<String, Object?> json) => _$ProductionPlanningBoardFromJson(json);
  
  /// Capacity against load per work centre and day, as `GET /production/capacity`.
  final List<ProductionCapacityCentre> centres;
  final DateTime from;

  /// Open operations of released and in-progress orders on those work centres that start on or.
  /// before `to`, in order of start.
  final List<ProductionBoardOperation> operations;
  final DateTime to;

  Map<String, Object?> toJson() => _$ProductionPlanningBoardToJson(this);
}
