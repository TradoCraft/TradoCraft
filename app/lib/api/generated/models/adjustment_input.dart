// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'adjustment_input.g.dart';

@JsonSerializable()
class AdjustmentInput {
  const AdjustmentInput({
    required this.id,
    required this.locationId,
    required this.note,
    required this.productId,
    this.delta,
    this.expiryDate,
    this.lotId,
    this.lotNumber,
    this.newQuantity,
  });
  
  factory AdjustmentInput.fromJson(Map<String, Object?> json) => _$AdjustmentInputFromJson(json);
  
  /// ...or change it by this much (negative takes stock away).
  @JsonKey(includeIfNull: false)
  final String? delta;
  @JsonKey(includeIfNull: false,name: 'expiry_date')
  final DateTime? expiryDate;
  final String id;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;

  /// Lot-tracked stock that was found: the lot number (created if new).
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;

  /// Set the stock at the location to this quantity...
  @JsonKey(includeIfNull: false,name: 'new_quantity')
  final String? newQuantity;

  /// Why; required.
  final String note;
  @JsonKey(name: 'product_id')
  final String productId;

  Map<String, Object?> toJson() => _$AdjustmentInputToJson(this);
}
