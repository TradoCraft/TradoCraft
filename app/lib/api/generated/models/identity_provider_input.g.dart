// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_provider_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IdentityProviderInput _$IdentityProviderInputFromJson(
  Map<String, dynamic> json,
) => IdentityProviderInput(
  audience: json['audience'] as String,
  issuer: json['issuer'] as String,
  name: json['name'] as String,
  algorithms: (json['algorithms'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  allowedEmailDomains: (json['allowed_email_domains'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  clientId: json['client_id'] as String?,
  confirmLockout: json['confirm_lockout'] as bool?,
  emailClaim: json['email_claim'] as String?,
  emailPolicy: json['email_policy'] as String?,
  enabled: json['enabled'] as bool?,
  scopes: json['scopes'] as String?,
  verifiedClaim: json['verified_claim'] as String?,
);

Map<String, dynamic> _$IdentityProviderInputToJson(
  IdentityProviderInput instance,
) => <String, dynamic>{
  'algorithms': ?instance.algorithms,
  'allowed_email_domains': ?instance.allowedEmailDomains,
  'audience': instance.audience,
  'client_id': ?instance.clientId,
  'confirm_lockout': ?instance.confirmLockout,
  'email_claim': ?instance.emailClaim,
  'email_policy': ?instance.emailPolicy,
  'enabled': ?instance.enabled,
  'issuer': instance.issuer,
  'name': instance.name,
  'scopes': ?instance.scopes,
  'verified_claim': ?instance.verifiedClaim,
};
