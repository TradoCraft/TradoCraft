// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'delivery_ship_to_input.g.dart';

@JsonSerializable()
class DeliveryShipToInput {
  const DeliveryShipToInput({
    required this.countryCode,
    required this.name,
    this.city,
    this.postalCode,
    this.street,
  });
  
  factory DeliveryShipToInput.fromJson(Map<String, Object?> json) => _$DeliveryShipToInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? city;
  @JsonKey(name: 'country_code')
  final String countryCode;
  final String name;
  @JsonKey(includeIfNull: false,name: 'postal_code')
  final String? postalCode;
  @JsonKey(includeIfNull: false)
  final String? street;

  Map<String, Object?> toJson() => _$DeliveryShipToInputToJson(this);
}
