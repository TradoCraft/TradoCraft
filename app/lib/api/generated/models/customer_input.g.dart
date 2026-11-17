// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CustomerInput _$CustomerInputFromJson(Map<String, dynamic> json) =>
    CustomerInput(
      code: json['code'] as String,
      name: json['name'] as String,
      priceZoneId: json['price_zone_id'] as String,
      active: json['active'] as bool?,
      city: json['city'] as String?,
      countryCode: json['country_code'] as String?,
      discountPercent: json['discount_percent'] as String?,
      email: json['email'] as String?,
      expectedVersion: (json['expected_version'] as num?)?.toInt(),
      language: json['language'] as String?,
      paymentTermsDays: (json['payment_terms_days'] as num?)?.toInt(),
      phone: json['phone'] as String?,
      postalCode: json['postal_code'] as String?,
      street: json['street'] as String?,
      vatNumber: json['vat_number'] as String?,
      vatRegime: json['vat_regime'] as String?,
    );

Map<String, dynamic> _$CustomerInputToJson(CustomerInput instance) =>
    <String, dynamic>{
      'active': ?instance.active,
      'city': ?instance.city,
      'code': instance.code,
      'country_code': ?instance.countryCode,
      'discount_percent': ?instance.discountPercent,
      'email': ?instance.email,
      'expected_version': ?instance.expectedVersion,
      'language': ?instance.language,
      'name': instance.name,
      'payment_terms_days': ?instance.paymentTermsDays,
      'phone': ?instance.phone,
      'postal_code': ?instance.postalCode,
      'price_zone_id': instance.priceZoneId,
      'street': ?instance.street,
      'vat_number': ?instance.vatNumber,
      'vat_regime': ?instance.vatRegime,
    };
