// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'delivery_ship_to.g.dart';

@JsonSerializable()
class DeliveryShipTo {
  const DeliveryShipTo({
    required this.city,
    required this.countryCode,
    required this.name,
    required this.postalCode,
    required this.street,
  });
  
  factory DeliveryShipTo.fromJson(Map<String, Object?> json) => _$DeliveryShipToFromJson(json);
  
  final String city;
  @JsonKey(name: 'country_code')
  final String countryCode;
  final String name;
  @JsonKey(name: 'postal_code')
  final String postalCode;
  final String street;

  Map<String, Object?> toJson() => _$DeliveryShipToToJson(this);
}
