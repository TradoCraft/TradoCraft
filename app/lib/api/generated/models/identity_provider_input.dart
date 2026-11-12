// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'identity_provider_input.g.dart';

/// The settings of an identity provider. Optional fields take the defaults of the table.
@JsonSerializable()
class IdentityProviderInput {
  const IdentityProviderInput({
    required this.audience,
    required this.issuer,
    required this.name,
    this.algorithms,
    this.allowedEmailDomains,
    this.clientId,
    this.confirmLockout,
    this.emailClaim,
    this.emailPolicy,
    this.enabled,
    this.scopes,
    this.verifiedClaim,
  });
  
  factory IdentityProviderInput.fromJson(Map<String, Object?> json) => _$IdentityProviderInputFromJson(json);
  
  /// Subset of RS256, RS384, RS512, ES256, ES384, PS256, PS384, PS512; default all of them.
  @JsonKey(includeIfNull: false)
  final List<String>? algorithms;

  /// When not empty, only these e-mail domains can be bound by e-mail.
  @JsonKey(includeIfNull: false,name: 'allowed_email_domains')
  final List<String>? allowedEmailDomains;

  /// The audience tokens must carry (usually the API's application id).
  final String audience;

  /// Public client id for the interactive sign-in; none for a provider used with bearer.
  /// tokens only.
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;

  /// Acknowledge that this change can lock people out (see the 409 answers).
  @JsonKey(includeIfNull: false,name: 'confirm_lockout')
  final bool? confirmLockout;

  /// Default `email`.
  @JsonKey(includeIfNull: false,name: 'email_claim')
  final String? emailClaim;

  /// Default `require_verified_claim`.
  @JsonKey(includeIfNull: false,name: 'email_policy')
  final String? emailPolicy;

  /// Default true.
  @JsonKey(includeIfNull: false)
  final bool? enabled;

  /// `https://` issuer URL; must serve `/.well-known/openid-configuration`.
  final String issuer;

  /// Display name.
  final String name;

  /// Default `openid profile email`.
  @JsonKey(includeIfNull: false)
  final String? scopes;

  /// Default `email_verified` (Microsoft Entra ID: `xms_edov`).
  @JsonKey(includeIfNull: false,name: 'verified_claim')
  final String? verifiedClaim;

  Map<String, Object?> toJson() => _$IdentityProviderInputToJson(this);
}
