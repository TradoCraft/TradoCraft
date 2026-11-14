// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'ship_delivery_input.g.dart';

@JsonSerializable()
class ShipDeliveryInput {
  const ShipDeliveryInput({
    this.carrier,
    this.trackingNumber,
  });
  
  factory ShipDeliveryInput.fromJson(Map<String, Object?> json) => _$ShipDeliveryInputFromJson(json);
  
  /// Sets the carrier and tracking reference as part of shipping.
  @JsonKey(includeIfNull: false)
  final String? carrier;
  @JsonKey(includeIfNull: false,name: 'tracking_number')
  final String? trackingNumber;

  Map<String, Object?> toJson() => _$ShipDeliveryInputToJson(this);
}
