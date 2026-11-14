// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'receipt_input.g.dart';

@JsonSerializable()
class ReceiptInput {
  const ReceiptInput({
    required this.id,
    required this.locationId,
    required this.productId,
    required this.quantity,
    this.currency,
    this.expiryDate,
    this.lotNumber,
    this.note,
    this.reason,
    this.serialNumber,
    this.serialUnitId,
    this.unitCost,
    this.uom,
  });
  
  factory ReceiptInput.fromJson(Map<String, Object?> json) => _$ReceiptInputFromJson(json);
  
  /// Currency of `unit_cost` (default: the currency of the company).
  @JsonKey(includeIfNull: false)
  final String? currency;
  @JsonKey(includeIfNull: false,name: 'expiry_date')
  final DateTime? expiryDate;

  /// Chosen by the client; a retry with the same id changes nothing.
  final String id;
  @JsonKey(name: 'location_id')
  final String locationId;

  /// Lot-tracked products: the lot (created if new).
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  @JsonKey(includeIfNull: false)
  final String? note;
  @JsonKey(name: 'product_id')
  final String productId;
  final String quantity;

  /// manual_receipt (default) | return
  @JsonKey(includeIfNull: false)
  final String? reason;

  /// ...or a new serial number, which registers the unit.
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;

  /// Serial-tracked products: an existing unit that is in stock without a location...
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;

  /// What one stock unit cost (needs `inventory.cost`); default: the standard cost.
  @JsonKey(includeIfNull: false,name: 'unit_cost')
  final String? unitCost;

  /// Unit the quantity is entered in; default the stock unit of the product.
  @JsonKey(includeIfNull: false)
  final String? uom;

  Map<String, Object?> toJson() => _$ReceiptInputToJson(this);
}
