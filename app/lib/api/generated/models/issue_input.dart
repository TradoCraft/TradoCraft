// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'issue_input.g.dart';

@JsonSerializable()
class IssueInput {
  const IssueInput({
    required this.id,
    required this.locationId,
    required this.productId,
    required this.quantity,
    this.consumeReservationLine,
    this.customerId,
    this.lotId,
    this.note,
    this.reason,
    this.serialUnitId,
    this.uom,
  });
  
  factory IssueInput.fromJson(Map<String, Object?> json) => _$IssueInputFromJson(json);
  
  /// Ship or consume the stock reserved for this sales order line: only that reservation is.
  /// exempt from the "reserved for orders" check, at most its quantity can be taken, and it.
  /// shrinks (or closes as consumed) in the same transaction.
  @JsonKey(includeIfNull: false,name: 'consume_reservation_line')
  final String? consumeReservationLine;

  /// Serial units shipped: the customer (unless the unit has one).
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  final String id;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(includeIfNull: false)
  final String? note;
  @JsonKey(name: 'product_id')
  final String productId;
  final String quantity;

  /// consumption (default) | shipment | scrap | repair_use
  @JsonKey(includeIfNull: false)
  final String? reason;
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;
  @JsonKey(includeIfNull: false)
  final String? uom;

  Map<String, Object?> toJson() => _$IssueInputToJson(this);
}
