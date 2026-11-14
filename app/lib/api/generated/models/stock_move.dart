// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'stock_move.g.dart';

/// One row of the ledger, as shown to staff.
@JsonSerializable()
class StockMove {
  const StockMove({
    required this.createdAt,
    required this.createdByName,
    required this.fromLocation,
    required this.fromLocationId,
    required this.id,
    required this.kind,
    required this.note,
    required this.occurredAt,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.reason,
    required this.seq,
    required this.toLocation,
    required this.toLocationId,
    required this.unit,
    this.currency,
    this.enteredQuantity,
    this.enteredUom,
    this.lotId,
    this.lotNumber,
    this.referenceId,
    this.referenceType,
    this.reversedBy,
    this.reversedOf,
    this.serialNumber,
    this.serialUnitId,
    this.unitCost,
  });
  
  factory StockMove.fromJson(Map<String, Object?> json) => _$StockMoveFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'created_by_name')
  final String createdByName;

  /// Currency of `unit_cost`. Only with `inventory.cost`.
  @JsonKey(includeIfNull: false)
  final String? currency;

  /// What the user typed, when it was in another unit than the stock unit.
  @JsonKey(includeIfNull: false,name: 'entered_quantity')
  final String? enteredQuantity;
  @JsonKey(includeIfNull: false,name: 'entered_uom')
  final String? enteredUom;
  @JsonKey(name: 'from_location')
  final String fromLocation;
  @JsonKey(name: 'from_location_id')
  final String fromLocationId;
  final String id;

  /// receipt | issue | transfer | adjustment
  final String kind;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  final String note;
  @JsonKey(name: 'occurred_at')
  final DateTime occurredAt;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  final String quantity;
  final String reason;
  @JsonKey(includeIfNull: false,name: 'reference_id')
  final String? referenceId;
  @JsonKey(includeIfNull: false,name: 'reference_type')
  final String? referenceType;

  /// The move that reversed this one.
  @JsonKey(includeIfNull: false,name: 'reversed_by')
  final String? reversedBy;

  /// The move this one reverses.
  @JsonKey(includeIfNull: false,name: 'reversed_of')
  final String? reversedOf;

  /// Position in the ledger; moves are shown newest first by this number.
  final int seq;
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;
  @JsonKey(name: 'to_location')
  final String toLocation;
  @JsonKey(name: 'to_location_id')
  final String toLocationId;

  /// The stock unit the quantity is in.
  final String unit;

  /// Cost per stock unit: what the posting module booked, else the standard cost of the product.
  /// at the time of the move. Only with `inventory.cost`.
  @JsonKey(includeIfNull: false,name: 'unit_cost')
  final String? unitCost;

  Map<String, Object?> toJson() => _$StockMoveToJson(this);
}
