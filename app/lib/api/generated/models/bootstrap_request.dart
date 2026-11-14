// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'bootstrap_request.g.dart';

/// Body of `POST /setup/bootstrap`: the company spec plus the token, when the server has one.
@JsonSerializable()
class BootstrapRequest {
  const BootstrapRequest({
    required this.adminDisplayName,
    required this.adminEmail,
    required this.countryCode,
    required this.currency,
    required this.defaultLanguage,
    required this.name,
    this.legalName,
    this.vatNumber,
    this.token,
  });
  
  factory BootstrapRequest.fromJson(Map<String, Object?> json) => _$BootstrapRequestFromJson(json);
  
  /// Display name of the first administrator.
  @JsonKey(name: 'admin_display_name')
  final String adminDisplayName;

  /// E-mail of the first administrator (created when no such user exists).
  @JsonKey(name: 'admin_email')
  final String adminEmail;

  /// ISO 3166 alpha-2 country code.
  @JsonKey(name: 'country_code')
  final String countryCode;

  /// ISO 4217 currency code.
  final String currency;

  /// One of nl, fr, en, de, es.
  @JsonKey(name: 'default_language')
  final String defaultLanguage;

  /// Registered name when it differs from `name`.
  @JsonKey(includeIfNull: false,name: 'legal_name')
  final String? legalName;

  /// Trading name; must be unique (case-insensitive).
  final String name;

  /// VAT number, for example `BE0123456749`.
  @JsonKey(includeIfNull: false,name: 'vat_number')
  final String? vatNumber;

  /// The `BOOTSTRAP_TOKEN`; required whenever the server has one.
  @JsonKey(includeIfNull: false)
  final String? token;

  Map<String, Object?> toJson() => _$BootstrapRequestToJson(this);
}
