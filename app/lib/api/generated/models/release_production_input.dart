// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'release_production_input.g.dart';

@JsonSerializable()
class ReleaseProductionInput {
  const ReleaseProductionInput({
    this.divisionId,
    this.notes,
    this.orderId,
    this.orderLineId,
    this.parentOrderId,
    this.plannedReadyDate,
    this.productId,
    this.quantity,
  });

  factory ReleaseProductionInput.fromJson(Map<String, Object?> json) =>
      _$ReleaseProductionInputFromJson(json);

  /// Defaults to the division that normally builds the product.
  @JsonKey(includeIfNull: false, name: 'division_id')
  final String? divisionId;
  @JsonKey(includeIfNull: false)
  final String? notes;

  /// Release a line of a confirmed sales order (with `order_line_id`), or leave both out to build.
  /// for stock (with `product_id` and `quantity`).
  @JsonKey(includeIfNull: false, name: 'order_id')
  final String? orderId;
  @JsonKey(includeIfNull: false, name: 'order_line_id')
  final String? orderLineId;

  /// A subassembly order made for a component of this production order.
  @JsonKey(includeIfNull: false, name: 'parent_order_id')
  final String? parentOrderId;
  @JsonKey(includeIfNull: false, name: 'planned_ready_date')
  final DateTime? plannedReadyDate;
  @JsonKey(includeIfNull: false, name: 'product_id')
  final String? productId;

  /// In the stock unit of the product. For an order line it defaults to what is still to be built.
  @JsonKey(includeIfNull: false)
  final String? quantity;

  Map<String, Object?> toJson() => _$ReleaseProductionInputToJson(this);
}
