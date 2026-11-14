// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vies_lookup.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ViesLookup _$ViesLookupFromJson(Map<String, dynamic> json) => ViesLookup(
  state: ViesState.fromJson(json['state'] as String),
  address: json['address'] as String?,
  city: json['city'] as String?,
  name: json['name'] as String?,
  postalCode: json['postal_code'] as String?,
  reason: json['reason'] as String?,
  street: json['street'] as String?,
);

Map<String, dynamic> _$ViesLookupToJson(ViesLookup instance) =>
    <String, dynamic>{
      'address': ?instance.address,
      'city': ?instance.city,
      'name': ?instance.name,
      'postal_code': ?instance.postalCode,
      'reason': ?instance.reason,
      'state': instance.state,
      'street': ?instance.street,
    };
