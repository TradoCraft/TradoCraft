// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'line_availability.dart';

part 'order_availability.g.dart';

@JsonSerializable()
class OrderAvailability {
  const OrderAvailability({
    required this.lines,
    required this.orderId,
    required this.orderNumber,
    required this.orderStatus,
    required this.reservable,
  });
  
  factory OrderAvailability.fromJson(Map<String, Object?> json) => _$OrderAvailabilityFromJson(json);
  
  final List<LineAvailability> lines;
  @JsonKey(name: 'order_id')
  final String orderId;
  @JsonKey(name: 'order_number')
  final String orderNumber;
  @JsonKey(name: 'order_status')
  final String orderStatus;

  /// Stock can be reserved: the customer has confirmed and the order is not cancelled.
  final bool reservable;

  Map<String, Object?> toJson() => _$OrderAvailabilityToJson(this);
}
