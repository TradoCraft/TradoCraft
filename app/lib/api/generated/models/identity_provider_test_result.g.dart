// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_provider_test_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IdentityProviderTestResult _$IdentityProviderTestResultFromJson(
  Map<String, dynamic> json,
) => IdentityProviderTestResult(
  discoveryReachable: json['discovery_reachable'] as bool,
  issuerMatch: json['issuer_match'] as bool,
  keyAlgorithms: (json['key_algorithms'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  keyCount: (json['key_count'] as num).toInt(),
  claimsSupported: (json['claims_supported'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  discoveryIssuer: json['discovery_issuer'] as String?,
  error: json['error'] as String?,
  token: json['token'] == null
      ? null
      : TokenTestResult.fromJson(json['token'] as Map<String, dynamic>),
);

Map<String, dynamic> _$IdentityProviderTestResultToJson(
  IdentityProviderTestResult instance,
) => <String, dynamic>{
  'claims_supported': ?instance.claimsSupported,
  'discovery_issuer': ?instance.discoveryIssuer,
  'discovery_reachable': instance.discoveryReachable,
  'error': ?instance.error,
  'issuer_match': instance.issuerMatch,
  'key_algorithms': instance.keyAlgorithms,
  'key_count': instance.keyCount,
  'token': ?instance.token,
};
