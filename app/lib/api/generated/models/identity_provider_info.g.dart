// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_provider_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IdentityProviderInfo _$IdentityProviderInfoFromJson(
  Map<String, dynamic> json,
) => IdentityProviderInfo(
  algorithms: (json['algorithms'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  allowedEmailDomains: (json['allowed_email_domains'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  audience: json['audience'] as String,
  emailClaim: json['email_claim'] as String,
  emailPolicy: json['email_policy'] as String,
  enabled: json['enabled'] as bool,
  issuer: json['issuer'] as String,
  name: json['name'] as String,
  readOnly: json['read_only'] as bool,
  scopes: json['scopes'] as String,
  source: json['source'] as String,
  verifiedClaim: json['verified_claim'] as String,
  clientId: json['client_id'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  id: json['id'] as String?,
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$IdentityProviderInfoToJson(
  IdentityProviderInfo instance,
) => <String, dynamic>{
  'algorithms': instance.algorithms,
  'allowed_email_domains': instance.allowedEmailDomains,
  'audience': instance.audience,
  'client_id': ?instance.clientId,
  'created_at': ?instance.createdAt?.toIso8601String(),
  'email_claim': instance.emailClaim,
  'email_policy': instance.emailPolicy,
  'enabled': instance.enabled,
  'id': ?instance.id,
  'issuer': instance.issuer,
  'name': instance.name,
  'read_only': instance.readOnly,
  'scopes': instance.scopes,
  'source': instance.source,
  'updated_at': ?instance.updatedAt?.toIso8601String(),
  'verified_claim': instance.verifiedClaim,
};
