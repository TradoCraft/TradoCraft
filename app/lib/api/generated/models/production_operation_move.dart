// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_move_conflict.dart';
import 'production_order.dart';

part 'production_operation_move.g.dart';

@JsonSerializable()
class ProductionOperationMove {
  const ProductionOperationMove({
    required this.applied,
    required this.conflicts,
    this.order,
  });
  
  factory ProductionOperationMove.fromJson(Map<String, Object?> json) => _$ProductionOperationMoveFromJson(json);
  
  /// False for a dry run.
  final bool applied;
  final List<ProductionMoveConflict> conflicts;

  /// The production order after the move.
  @JsonKey(includeIfNull: false)
  final ProductionOrder? order;

  Map<String, Object?> toJson() => _$ProductionOperationMoveToJson(this);
}
