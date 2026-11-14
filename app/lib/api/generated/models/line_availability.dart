// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'line_availability.g.dart';

@JsonSerializable()
class LineAvailability {
  const LineAvailability({
    required this.available,
    required this.consumed,
    required this.description,
    required this.expired,
    required this.onHand,
    required this.orderLineId,
    required this.ordered,
    required this.orderedStock,
    required this.position,
    required this.productCode,
    required this.reserved,
    required this.reservedTotal,
    required this.shortfall,
    required this.state,
    required this.unit,
    this.productId,
  });
  
  factory LineAvailability.fromJson(Map<String, Object?> json) => _$LineAvailabilityFromJson(json);
  
  /// Available to promise: on hand minus expired stock minus what is reserved in good lots.
  final String available;

  /// Already shipped from reservations of this line, in the stock unit.
  final String consumed;
  final String description;

  /// Of the on hand quantity: in lots that are past their expiry date (not available).
  final String expired;

  /// In the warehouses.
  @JsonKey(name: 'on_hand')
  final String onHand;
  @JsonKey(name: 'order_line_id')
  final String orderLineId;

  /// Ordered quantity, in the unit of the line.
  final String ordered;

  /// Ordered quantity in the stock unit of the product (0 when the line is not stocked).
  @JsonKey(name: 'ordered_stock')
  final String orderedStock;
  final int position;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// Reserved for this line, in the stock unit.
  final String reserved;

  /// Reserved for all orders.
  @JsonKey(name: 'reserved_total')
  final String reservedTotal;

  /// What neither the reservation nor free stock covers.
  final String shortfall;

  /// reserved | available | partial | short | not_stocked
  final String state;
  final String unit;

  Map<String, Object?> toJson() => _$LineAvailabilityToJson(this);
}
