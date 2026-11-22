// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'billing_party.g.dart';

@JsonSerializable()
class BillingParty {
  const BillingParty({
    required this.city,
    required this.countryCode,
    required this.name,
    required this.postalCode,
    required this.street,
    this.vatNumber,
  });
  
  factory BillingParty.fromJson(Map<String, Object?> json) => _$BillingPartyFromJson(json);
  
  final String city;
  @JsonKey(name: 'country_code')
  final String countryCode;
  final String name;
  @JsonKey(name: 'postal_code')
  final String postalCode;
  final String street;
  @JsonKey(includeIfNull: false,name: 'vat_number')
  final String? vatNumber;

  Map<String, Object?> toJson() => _$BillingPartyToJson(this);
}
