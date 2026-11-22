// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_party.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BillingParty _$BillingPartyFromJson(Map<String, dynamic> json) => BillingParty(
  city: json['city'] as String,
  countryCode: json['country_code'] as String,
  name: json['name'] as String,
  postalCode: json['postal_code'] as String,
  street: json['street'] as String,
  vatNumber: json['vat_number'] as String?,
);

Map<String, dynamic> _$BillingPartyToJson(BillingParty instance) =>
    <String, dynamic>{
      'city': instance.city,
      'country_code': instance.countryCode,
      'name': instance.name,
      'postal_code': instance.postalCode,
      'street': instance.street,
      'vat_number': ?instance.vatNumber,
    };
