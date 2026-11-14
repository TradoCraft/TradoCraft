// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_sub_order.g.dart';

/// A production order released for a subassembly of another one.
@JsonSerializable()
class ProductionSubOrder {
  const ProductionSubOrder({
    required this.id,
    required this.number,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.status,
    required this.unit,
    this.plannedReadyDate,
    this.scheduledEnd,
  });
  
  factory ProductionSubOrder.fromJson(Map<String, Object?> json) => _$ProductionSubOrderFromJson(json);
  
  final String id;
  final String number;
  @JsonKey(includeIfNull: false,name: 'planned_ready_date')
  final DateTime? plannedReadyDate;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  final String quantity;

  /// When its last open operation is scheduled to end.
  @JsonKey(includeIfNull: false,name: 'scheduled_end')
  final DateTime? scheduledEnd;

  /// released | in_progress | completed | cancelled
  final String status;
  final String unit;

  Map<String, Object?> toJson() => _$ProductionSubOrderToJson(this);
}
