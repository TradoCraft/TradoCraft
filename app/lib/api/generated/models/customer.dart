// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'customer.g.dart';

@JsonSerializable()
class Customer {
  const Customer({
    required this.active,
    required this.city,
    required this.code,
    required this.countryCode,
    required this.id,
    required this.language,
    required this.name,
    required this.postalCode,
    required this.street,
    required this.vatRegime,
    this.discountPercent,
    this.email,
    this.paymentTermsDays,
    this.phone,
    this.priceZoneCode,
    this.priceZoneId,
    this.vatNumber,
  });
  
  factory Customer.fromJson(Map<String, Object?> json) => _$CustomerFromJson(json);
  
  final bool active;
  final String city;
  final String code;
  @JsonKey(name: 'country_code')
  final String countryCode;
  @JsonKey(includeIfNull: false,name: 'discount_percent')
  final String? discountPercent;
  @JsonKey(includeIfNull: false)
  final String? email;
  final String id;
  final String language;
  final String name;
  @JsonKey(includeIfNull: false,name: 'payment_terms_days')
  final int? paymentTermsDays;
  @JsonKey(includeIfNull: false)
  final String? phone;
  @JsonKey(name: 'postal_code')
  final String postalCode;
  @JsonKey(includeIfNull: false,name: 'price_zone_code')
  final String? priceZoneCode;
  @JsonKey(includeIfNull: false,name: 'price_zone_id')
  final String? priceZoneId;
  final String street;
  @JsonKey(includeIfNull: false,name: 'vat_number')
  final String? vatNumber;

  /// `domestic` (VAT charged), `intra_eu` (reverse charge) or `outside_eu`.
  @JsonKey(name: 'vat_regime')
  final String vatRegime;

  Map<String, Object?> toJson() => _$CustomerToJson(this);
}
