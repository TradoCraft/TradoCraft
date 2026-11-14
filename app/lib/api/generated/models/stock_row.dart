// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'stock_row.g.dart';

/// Stock of one product at one location and lot.
@JsonSerializable()
class StockRow {
  const StockRow({
    required this.available,
    required this.location,
    required this.locationId,
    required this.onHand,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.reserved,
    required this.tracking,
    required this.unit,
    required this.warehouseId,
    required this.warehouseKind,
    this.expiryDate,
    this.lotId,
    this.lotNumber,
  });
  
  factory StockRow.fromJson(Map<String, Object?> json) => _$StockRowFromJson(json);
  
  /// On hand minus reserved; negative when stock was adjusted away from reservations.
  final String available;
  @JsonKey(includeIfNull: false,name: 'expiry_date')
  final DateTime? expiryDate;

  /// `WAREHOUSE/LOCATION`
  final String location;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  @JsonKey(name: 'on_hand')
  final String onHand;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  final String reserved;
  final String tracking;
  final String unit;
  @JsonKey(name: 'warehouse_id')
  final String warehouseId;
  @JsonKey(name: 'warehouse_kind')
  final String warehouseKind;

  Map<String, Object?> toJson() => _$StockRowToJson(this);
}
