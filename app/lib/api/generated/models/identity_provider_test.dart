// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'identity_provider_input.dart';

part 'identity_provider_test.g.dart';

/// A draft configuration (or an existing provider) and optionally a token to try it with.
@JsonSerializable()
class IdentityProviderTest {
  const IdentityProviderTest({
    this.config,
    this.id,
    this.sampleToken,
  });
  
  factory IdentityProviderTest.fromJson(Map<String, Object?> json) => _$IdentityProviderTestFromJson(json);
  
  /// A draft configuration to test.
  @JsonKey(includeIfNull: false)
  final IdentityProviderInput? config;

  /// An existing provider to test; ignored when `config` is given.
  @JsonKey(includeIfNull: false)
  final String? id;

  /// An access token of this provider. It is checked and discarded: never stored or logged.
  @JsonKey(includeIfNull: false,name: 'sample_token')
  final String? sampleToken;

  Map<String, Object?> toJson() => _$IdentityProviderTestToJson(this);
}
