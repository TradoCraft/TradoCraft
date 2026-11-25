// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_board_operation.g.dart';

/// An open operation on the board.
@JsonSerializable()
class ProductionBoardOperation {
  const ProductionBoardOperation({
    required this.id,
    required this.lateValue,
    required this.locked,
    required this.name,
    required this.orderNumber,
    required this.plannedEnd,
    required this.plannedMinutes,
    required this.plannedStart,
    required this.position,
    required this.productName,
    required this.productionOrderId,
    required this.status,
    required this.workCentreId,
    this.plannedReadyDate,
    this.predecessorEnd,
    this.successorStart,
  });
  
  factory ProductionBoardOperation.fromJson(Map<String, Object?> json) => _$ProductionBoardOperationFromJson(json);
  
  final String id;

  /// Planned to end before the period starts: still to do, so it is shown at the start.
  /// The name has been replaced because it contains a keyword. Original name: `late`.
  @JsonKey(name: 'late')
  final bool lateValue;

  /// Only a pending operation can be dragged.
  final bool locked;
  final String name;
  @JsonKey(name: 'order_number')
  final String orderNumber;
  @JsonKey(name: 'planned_end')
  final DateTime plannedEnd;
  @JsonKey(name: 'planned_minutes')
  final int plannedMinutes;

  /// The order's planned-ready date.
  @JsonKey(includeIfNull: false,name: 'planned_ready_date')
  final DateTime? plannedReadyDate;
  @JsonKey(name: 'planned_start')
  final DateTime plannedStart;
  final int position;

  /// When the previous operation of the order ends.
  @JsonKey(includeIfNull: false,name: 'predecessor_end')
  final DateTime? predecessorEnd;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'production_order_id')
  final String productionOrderId;

  /// `pending` or `in_progress`.
  final String status;

  /// When the next operation of the order starts.
  @JsonKey(includeIfNull: false,name: 'successor_start')
  final DateTime? successorStart;
  @JsonKey(name: 'work_centre_id')
  final String workCentreId;

  Map<String, Object?> toJson() => _$ProductionBoardOperationToJson(this);
}
