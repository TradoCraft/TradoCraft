// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'delivery_note_line.g.dart';

@JsonSerializable()
class DeliveryNoteLine {
  const DeliveryNoteLine({
    required this.id,
    required this.location,
    required this.locationId,
    required this.orderLineId,
    required this.orderPosition,
    required this.position,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.tracking,
    required this.unit,
    this.lotId,
    this.lotNumber,
    this.serialNumber,
    this.serialUnitId,
    this.stockMoveId,
  });
  
  factory DeliveryNoteLine.fromJson(Map<String, Object?> json) => _$DeliveryNoteLineFromJson(json);
  
  final String id;
  final String location;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  @JsonKey(name: 'order_line_id')
  final String orderLineId;

  /// Position of the order line on the order.
  @JsonKey(name: 'order_position')
  final int orderPosition;
  final int position;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;

  /// In the stock unit of the product.
  final String quantity;
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;

  /// The stock move that took the goods out, once shipped.
  @JsonKey(includeIfNull: false,name: 'stock_move_id')
  final String? stockMoveId;

  /// none | serial | lot: serial-tracked lines need a serial number before shipping.
  final String tracking;
  final String unit;

  Map<String, Object?> toJson() => _$DeliveryNoteLineToJson(this);
}
