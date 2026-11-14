// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bootstrap_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BootstrapRequest _$BootstrapRequestFromJson(Map<String, dynamic> json) =>
    BootstrapRequest(
      adminDisplayName: json['admin_display_name'] as String,
      adminEmail: json['admin_email'] as String,
      countryCode: json['country_code'] as String,
      currency: json['currency'] as String,
      defaultLanguage: json['default_language'] as String,
      name: json['name'] as String,
      legalName: json['legal_name'] as String?,
      vatNumber: json['vat_number'] as String?,
      token: json['token'] as String?,
    );

Map<String, dynamic> _$BootstrapRequestToJson(BootstrapRequest instance) =>
    <String, dynamic>{
      'admin_display_name': instance.adminDisplayName,
      'admin_email': instance.adminEmail,
      'country_code': instance.countryCode,
      'currency': instance.currency,
      'default_language': instance.defaultLanguage,
      'legal_name': ?instance.legalName,
      'name': instance.name,
      'vat_number': ?instance.vatNumber,
      'token': ?instance.token,
    };
