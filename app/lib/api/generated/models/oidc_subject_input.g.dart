// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'oidc_subject_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OidcSubjectInput _$OidcSubjectInputFromJson(Map<String, dynamic> json) =>
    OidcSubjectInput(
      issuer: json['issuer'] as String?,
      subject: json['subject'] as String?,
    );

Map<String, dynamic> _$OidcSubjectInputToJson(OidcSubjectInput instance) =>
    <String, dynamic>{'issuer': ?instance.issuer, 'subject': ?instance.subject};
