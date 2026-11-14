// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'delivery_line_input.g.dart';

@JsonSerializable()
class DeliveryLineInput {
  const DeliveryLineInput({
    required this.locationId,
    required this.orderLineId,
    required this.quantity,
    this.lotId,
    this.serialUnitId,
  });
  
  factory DeliveryLineInput.fromJson(Map<String, Object?> json) => _$DeliveryLineInputFromJson(json);
  
  @JsonKey(name: 'location_id')
  final String locationId;

  /// Needed for lot-tracked products.
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(name: 'order_line_id')
  final String orderLineId;

  /// In the stock unit of the product, at most four decimals; 1 for a serial-tracked product.
  final String quantity;

  /// Needed for serial-tracked products (before shipping).
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;

  Map<String, Object?> toJson() => _$DeliveryLineInputToJson(this);
}
