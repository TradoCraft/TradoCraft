// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'binding_result.dart';

part 'token_test_result.g.dart';

/// The result of checking a sample token.
@JsonSerializable()
class TokenTestResult {
  const TokenTestResult({
    required this.signatureOk,
    required this.valid,
    this.audienceOk,
    this.binding,
    this.email,
    this.emailVerified,
    this.expiryOk,
    this.issuerOk,
    this.notBeforeOk,
    this.reason,
    this.subject,
  });

  factory TokenTestResult.fromJson(Map<String, Object?> json) =>
      _$TokenTestResultFromJson(json);

  /// `aud` contains the configured audience.
  @JsonKey(includeIfNull: false, name: 'audience_ok')
  final bool? audienceOk;

  /// What a sign-in would do; only for a valid token.
  @JsonKey(includeIfNull: false)
  final BindingResult? binding;

  /// The e-mail address found in the configured e-mail claim.
  @JsonKey(includeIfNull: false)
  final String? email;

  /// The value of the configured verification claim, read as a boolean.
  @JsonKey(includeIfNull: false, name: 'email_verified')
  final bool? emailVerified;

  /// `exp` is in the future.
  @JsonKey(includeIfNull: false, name: 'expiry_ok')
  final bool? expiryOk;

  /// `iss` equals the configured issuer.
  @JsonKey(includeIfNull: false, name: 'issuer_ok')
  final bool? issuerOk;

  /// `nbf` is not in the future.
  @JsonKey(includeIfNull: false, name: 'not_before_ok')
  final bool? notBeforeOk;

  /// Why the token is not valid.
  @JsonKey(includeIfNull: false)
  final String? reason;

  /// The signature verified with a published key.
  @JsonKey(name: 'signature_ok')
  final bool signatureOk;

  /// The token's subject.
  @JsonKey(includeIfNull: false)
  final String? subject;

  /// All checks passed.
  final bool valid;

  Map<String, Object?> toJson() => _$TokenTestResultToJson(this);
}
