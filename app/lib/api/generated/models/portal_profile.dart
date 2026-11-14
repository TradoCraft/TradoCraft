// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'portal_profile.g.dart';

/// Who is logged in, as the portal shows it.
@JsonSerializable()
class PortalProfile {
  const PortalProfile({
    required this.addressForm,
    required this.contactId,
    required this.customerLanguage,
    required this.customerName,
    required this.effectiveLanguage,
    required this.firstName,
    required this.fullName,
    required this.greeting,
    required this.jobTitle,
    required this.lastName,
    required this.roles,
    required this.scope,
    required this.title,
    this.email,
    this.language,
  });
  
  factory PortalProfile.fromJson(Map<String, Object?> json) => _$PortalProfileFromJson(json);
  
  /// formal | informal
  @JsonKey(name: 'address_form')
  final String addressForm;
  @JsonKey(name: 'contact_id')
  final String contactId;
  @JsonKey(name: 'customer_language')
  final String customerLanguage;
  @JsonKey(name: 'customer_name')
  final String customerName;

  /// The language the portal and our e-mails use for this person.
  @JsonKey(name: 'effective_language')
  final String effectiveLanguage;
  @JsonKey(includeIfNull: false)
  final String? email;
  @JsonKey(name: 'first_name')
  final String firstName;
  @JsonKey(name: 'full_name')
  final String fullName;
  final String greeting;
  @JsonKey(name: 'job_title')
  final String jobTitle;

  /// The person's own language; null means the same as the company.
  @JsonKey(includeIfNull: false)
  final String? language;
  @JsonKey(name: 'last_name')
  final String lastName;
  final List<String> roles;

  /// own | customer
  final String scope;

  /// mr | ms | none
  final String title;

  Map<String, Object?> toJson() => _$PortalProfileToJson(this);
}
