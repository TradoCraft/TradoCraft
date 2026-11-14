// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reserve_input.g.dart';

@JsonSerializable()
class ReserveInput {
  const ReserveInput({
    required this.quantity,
    this.locationId,
    this.lotId,
    this.warehouseId,
  });
  
  factory ReserveInput.fromJson(Map<String, Object?> json) => _$ReserveInputFromJson(json);
  
  /// ...or this location...
  @JsonKey(includeIfNull: false,name: 'location_id')
  final String? locationId;

  /// ...or this lot.
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;

  /// The quantity that should be reserved for the line in total, in the stock unit of the.
  /// product. More reserves additional stock, less releases the newest allocations, 0 releases all.
  final String quantity;

  /// Take additional stock only from this warehouse...
  @JsonKey(includeIfNull: false,name: 'warehouse_id')
  final String? warehouseId;

  Map<String, Object?> toJson() => _$ReserveInputToJson(this);
}
