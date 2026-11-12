// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'public_provider.g.dart';

/// What the sign-in page needs to know about an enabled provider.
@JsonSerializable()
class PublicProvider {
  const PublicProvider({
    required this.issuer,
    required this.name,
    required this.scopes,
    required this.source,
    this.clientId,
  });
  
  factory PublicProvider.fromJson(Map<String, Object?> json) => _$PublicProviderFromJson(json);
  
  /// Public client id of the interactive sign-in.
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;

  /// Issuer URL.
  final String issuer;

  /// Display name.
  final String name;

  /// Scopes to ask for.
  final String scopes;

  /// `database` or `env` (the read-only fallback from `OIDC_ISSUER`), so the page can label it.
  final String source;

  Map<String, Object?> toJson() => _$PublicProviderToJson(this);
}
