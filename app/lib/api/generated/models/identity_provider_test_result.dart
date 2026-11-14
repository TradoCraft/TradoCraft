// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'token_test_result.dart';

part 'identity_provider_test_result.g.dart';

/// The outcome of testing a provider configuration.
@JsonSerializable()
class IdentityProviderTestResult {
  const IdentityProviderTestResult({
    required this.discoveryReachable,
    required this.issuerMatch,
    required this.keyAlgorithms,
    required this.keyCount,
    this.claimsSupported,
    this.discoveryIssuer,
    this.error,
    this.token,
  });
  
  factory IdentityProviderTestResult.fromJson(Map<String, Object?> json) => _$IdentityProviderTestResultFromJson(json);
  
  /// `claims_supported` if the provider advertises it.
  @JsonKey(includeIfNull: false,name: 'claims_supported')
  final List<String>? claimsSupported;

  /// The issuer the discovery document names.
  @JsonKey(includeIfNull: false,name: 'discovery_issuer')
  final String? discoveryIssuer;

  /// Discovery document and keys could be read.
  @JsonKey(name: 'discovery_reachable')
  final bool discoveryReachable;

  /// Why the provider could not be read.
  @JsonKey(includeIfNull: false)
  final String? error;

  /// The discovery `issuer` equals the configured issuer.
  @JsonKey(name: 'issuer_match')
  final bool issuerMatch;

  /// Algorithms (or key types) of the published keys.
  @JsonKey(name: 'key_algorithms')
  final List<String> keyAlgorithms;

  /// Number of keys in the JWKS.
  @JsonKey(name: 'key_count')
  final int keyCount;

  /// The result for the sample token, if one was given.
  @JsonKey(includeIfNull: false)
  final TokenTestResult? token;

  Map<String, Object?> toJson() => _$IdentityProviderTestResultToJson(this);
}
