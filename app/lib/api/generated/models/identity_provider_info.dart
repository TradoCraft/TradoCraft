// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'identity_provider_info.g.dart';

/// An identity provider as the admin screen shows it.
@JsonSerializable()
class IdentityProviderInfo {
  const IdentityProviderInfo({
    required this.algorithms,
    required this.allowedEmailDomains,
    required this.audience,
    required this.emailClaim,
    required this.emailPolicy,
    required this.enabled,
    required this.issuer,
    required this.name,
    required this.readOnly,
    required this.scopes,
    required this.source,
    required this.verifiedClaim,
    this.clientId,
    this.createdAt,
    this.id,
    this.updatedAt,
  });
  
  factory IdentityProviderInfo.fromJson(Map<String, Object?> json) => _$IdentityProviderInfoFromJson(json);
  
  /// Accepted JWS algorithms.
  final List<String> algorithms;

  /// When not empty, only these e-mail domains can be bound by e-mail.
  @JsonKey(name: 'allowed_email_domains')
  final List<String> allowedEmailDomains;

  /// The audience tokens must carry.
  final String audience;

  /// Public client id for the interactive sign-in.
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;

  /// When the provider was created.
  @JsonKey(includeIfNull: false,name: 'created_at')
  final DateTime? createdAt;

  /// Claim holding the e-mail address.
  @JsonKey(name: 'email_claim')
  final String emailClaim;

  /// `require_verified_claim`, `trust_provider_email` or `subject_only`.
  @JsonKey(name: 'email_policy')
  final String emailPolicy;

  /// Whether tokens of this provider are accepted.
  final bool enabled;

  /// Database id; absent for the environment provider.
  @JsonKey(includeIfNull: false)
  final String? id;

  /// Issuer URL (no trailing slash); the token's `iss` selects the provider.
  final String issuer;

  /// Display name.
  final String name;

  /// True for the environment provider: it cannot be changed or deleted here.
  @JsonKey(name: 'read_only')
  final bool readOnly;

  /// Scopes the interactive sign-in asks for.
  final String scopes;

  /// `database` or `env` (read-only emergency fallback from `OIDC_ISSUER`).
  final String source;

  /// When it was last changed.
  @JsonKey(includeIfNull: false,name: 'updated_at')
  final DateTime? updatedAt;

  /// Boolean claim used by `require_verified_claim`.
  @JsonKey(name: 'verified_claim')
  final String verifiedClaim;

  Map<String, Object?> toJson() => _$IdentityProviderInfoToJson(this);
}
