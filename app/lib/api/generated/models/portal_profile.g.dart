// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'portal_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PortalProfile _$PortalProfileFromJson(Map<String, dynamic> json) =>
    PortalProfile(
      addressForm: json['address_form'] as String,
      contactId: json['contact_id'] as String,
      customerLanguage: json['customer_language'] as String,
      customerName: json['customer_name'] as String,
      effectiveLanguage: json['effective_language'] as String,
      firstName: json['first_name'] as String,
      fullName: json['full_name'] as String,
      greeting: json['greeting'] as String,
      jobTitle: json['job_title'] as String,
      lastName: json['last_name'] as String,
      roles: (json['roles'] as List<dynamic>).map((e) => e as String).toList(),
      scope: json['scope'] as String,
      title: json['title'] as String,
      email: json['email'] as String?,
      language: json['language'] as String?,
      languages: (json['languages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$PortalProfileToJson(PortalProfile instance) =>
    <String, dynamic>{
      'address_form': instance.addressForm,
      'contact_id': instance.contactId,
      'customer_language': instance.customerLanguage,
      'customer_name': instance.customerName,
      'effective_language': instance.effectiveLanguage,
      'email': ?instance.email,
      'first_name': instance.firstName,
      'full_name': instance.fullName,
      'greeting': instance.greeting,
      'job_title': instance.jobTitle,
      'language': ?instance.language,
      'languages': ?instance.languages,
      'last_name': instance.lastName,
      'roles': instance.roles,
      'scope': instance.scope,
      'title': instance.title,
    };
