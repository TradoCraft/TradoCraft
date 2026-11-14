// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'company.g.dart';

/// A legal entity (own VAT number, own numbering, own stock and books).
@JsonSerializable()
class Company {
  const Company({
    required this.city,
    required this.countryCode,
    required this.currency,
    required this.defaultLanguage,
    required this.id,
    required this.isPrimary,
    required this.name,
    required this.postalCode,
    required this.street,
    this.email,
    this.iban,
    this.phone,
    this.vatNumber,
  });

  factory Company.fromJson(Map<String, Object?> json) =>
      _$CompanyFromJson(json);

  final String city;
  @JsonKey(name: 'country_code')
  final String countryCode;
  final String currency;
  @JsonKey(name: 'default_language')
  final String defaultLanguage;
  @JsonKey(includeIfNull: false)
  final String? email;
  @JsonKey(includeIfNull: false)
  final String? iban;
  final String id;

  /// True for the installation's primary company, whose administrators change the.
  /// installation-wide settings (identity providers, ADR 0055).
  @JsonKey(name: 'is_primary')
  final bool isPrimary;
  final String name;
  @JsonKey(includeIfNull: false)
  final String? phone;
  @JsonKey(name: 'postal_code')
  final String postalCode;
  final String street;
  @JsonKey(includeIfNull: false, name: 'vat_number')
  final String? vatNumber;

  Map<String, Object?> toJson() => _$CompanyToJson(this);
}
