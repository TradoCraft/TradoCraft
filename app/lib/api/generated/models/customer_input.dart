// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'customer_input.g.dart';

@JsonSerializable()
class CustomerInput {
  const CustomerInput({
    required this.code,
    required this.name,
    required this.priceZoneId,
    this.active,
    this.city,
    this.countryCode,
    this.discountPercent,
    this.email,
    this.language,
    this.paymentTermsDays,
    this.phone,
    this.postalCode,
    this.street,
    this.vatNumber,
    this.vatRegime,
  });
  
  factory CustomerInput.fromJson(Map<String, Object?> json) => _$CustomerInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false)
  final String? city;
  final String code;
  @JsonKey(includeIfNull: false,name: 'country_code')
  final String? countryCode;
  @JsonKey(includeIfNull: false,name: 'discount_percent')
  final String? discountPercent;
  @JsonKey(includeIfNull: false)
  final String? email;
  @JsonKey(includeIfNull: false)
  final String? language;
  final String name;
  @JsonKey(includeIfNull: false,name: 'payment_terms_days')
  final int? paymentTermsDays;
  @JsonKey(includeIfNull: false)
  final String? phone;
  @JsonKey(includeIfNull: false,name: 'postal_code')
  final String? postalCode;
  @JsonKey(name: 'price_zone_id')
  final String priceZoneId;
  @JsonKey(includeIfNull: false)
  final String? street;
  @JsonKey(includeIfNull: false,name: 'vat_number')
  final String? vatNumber;

  /// `domestic` (default), `intra_eu` or `outside_eu`.
  @JsonKey(includeIfNull: false,name: 'vat_regime')
  final String? vatRegime;

  Map<String, Object?> toJson() => _$CustomerInputToJson(this);
}
