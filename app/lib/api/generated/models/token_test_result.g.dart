// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'token_test_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TokenTestResult _$TokenTestResultFromJson(Map<String, dynamic> json) =>
    TokenTestResult(
      signatureOk: json['signature_ok'] as bool,
      valid: json['valid'] as bool,
      audienceOk: json['audience_ok'] as bool?,
      binding: json['binding'] == null
          ? null
          : BindingResult.fromJson(json['binding'] as Map<String, dynamic>),
      email: json['email'] as String?,
      emailVerified: json['email_verified'] as bool?,
      expiryOk: json['expiry_ok'] as bool?,
      issuerOk: json['issuer_ok'] as bool?,
      notBeforeOk: json['not_before_ok'] as bool?,
      reason: json['reason'] as String?,
      subject: json['subject'] as String?,
    );

Map<String, dynamic> _$TokenTestResultToJson(TokenTestResult instance) =>
    <String, dynamic>{
      'audience_ok': ?instance.audienceOk,
      'binding': ?instance.binding,
      'email': ?instance.email,
      'email_verified': ?instance.emailVerified,
      'expiry_ok': ?instance.expiryOk,
      'issuer_ok': ?instance.issuerOk,
      'not_before_ok': ?instance.notBeforeOk,
      'reason': ?instance.reason,
      'signature_ok': instance.signatureOk,
      'subject': ?instance.subject,
      'valid': instance.valid,
    };
