// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Company _$CompanyFromJson(Map<String, dynamic> json) => Company(
  city: json['city'] as String,
  countryCode: json['country_code'] as String,
  currency: json['currency'] as String,
  defaultLanguage: json['default_language'] as String,
  id: json['id'] as String,
  isPrimary: json['is_primary'] as bool,
  name: json['name'] as String,
  postalCode: json['postal_code'] as String,
  street: json['street'] as String,
  email: json['email'] as String?,
  iban: json['iban'] as String?,
  phone: json['phone'] as String?,
  vatNumber: json['vat_number'] as String?,
);

Map<String, dynamic> _$CompanyToJson(Company instance) => <String, dynamic>{
  'city': instance.city,
  'country_code': instance.countryCode,
  'currency': instance.currency,
  'default_language': instance.defaultLanguage,
  'email': ?instance.email,
  'iban': ?instance.iban,
  'id': instance.id,
  'is_primary': instance.isPrimary,
  'name': instance.name,
  'phone': ?instance.phone,
  'postal_code': instance.postalCode,
  'street': instance.street,
  'vat_number': ?instance.vatNumber,
};
