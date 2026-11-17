// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Customer _$CustomerFromJson(Map<String, dynamic> json) => Customer(
  active: json['active'] as bool,
  city: json['city'] as String,
  code: json['code'] as String,
  countryCode: json['country_code'] as String,
  id: json['id'] as String,
  language: json['language'] as String,
  name: json['name'] as String,
  postalCode: json['postal_code'] as String,
  street: json['street'] as String,
  vatRegime: json['vat_regime'] as String,
  discountPercent: json['discount_percent'] as String?,
  email: json['email'] as String?,
  paymentTermsDays: (json['payment_terms_days'] as num?)?.toInt(),
  phone: json['phone'] as String?,
  priceZoneCode: json['price_zone_code'] as String?,
  priceZoneId: json['price_zone_id'] as String?,
  vatNumber: json['vat_number'] as String?,
  version: (json['version'] as num?)?.toInt(),
);

Map<String, dynamic> _$CustomerToJson(Customer instance) => <String, dynamic>{
  'active': instance.active,
  'city': instance.city,
  'code': instance.code,
  'country_code': instance.countryCode,
  'discount_percent': ?instance.discountPercent,
  'email': ?instance.email,
  'id': instance.id,
  'language': instance.language,
  'name': instance.name,
  'payment_terms_days': ?instance.paymentTermsDays,
  'phone': ?instance.phone,
  'postal_code': instance.postalCode,
  'price_zone_code': ?instance.priceZoneCode,
  'price_zone_id': ?instance.priceZoneId,
  'street': instance.street,
  'vat_number': ?instance.vatNumber,
  'vat_regime': instance.vatRegime,
  'version': ?instance.version,
};
