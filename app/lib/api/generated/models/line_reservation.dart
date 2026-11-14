// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'allocation.dart';

part 'line_reservation.g.dart';

@JsonSerializable()
class LineReservation {
  const LineReservation({
    required this.allocations,
    required this.consumed,
    required this.orderLineId,
    required this.ordered,
    required this.productCode,
    required this.productId,
    required this.reserved,
  });
  
  factory LineReservation.fromJson(Map<String, Object?> json) => _$LineReservationFromJson(json);
  
  final List<Allocation> allocations;

  /// Already shipped from reservations of this line, in the stock unit. What is still to be.
  /// reserved is `ordered` minus `consumed`.
  final String consumed;
  @JsonKey(name: 'order_line_id')
  final String orderLineId;

  /// Ordered quantity in the stock unit of the product. 0 when the unit of the line no longer.
  /// converts and the response is for a release.
  final String ordered;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  final String reserved;

  Map<String, Object?> toJson() => _$LineReservationToJson(this);
}
