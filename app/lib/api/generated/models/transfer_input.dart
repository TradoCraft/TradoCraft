// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'transfer_input.g.dart';

@JsonSerializable()
class TransferInput {
  const TransferInput({
    required this.fromLocationId,
    required this.id,
    required this.productId,
    required this.quantity,
    required this.toLocationId,
    this.lotId,
    this.note,
    this.reason,
    this.serialUnitId,
    this.uom,
  });
  
  factory TransferInput.fromJson(Map<String, Object?> json) => _$TransferInputFromJson(json);
  
  @JsonKey(name: 'from_location_id')
  final String fromLocationId;
  final String id;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(includeIfNull: false)
  final String? note;
  @JsonKey(name: 'product_id')
  final String productId;
  final String quantity;

  /// transfer (default) | van_replenishment
  @JsonKey(includeIfNull: false)
  final String? reason;
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;
  @JsonKey(name: 'to_location_id')
  final String toLocationId;
  @JsonKey(includeIfNull: false)
  final String? uom;

  Map<String, Object?> toJson() => _$TransferInputToJson(this);
}
