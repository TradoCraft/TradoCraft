// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'phone_input.dart';

part 'contact_input.g.dart';

@JsonSerializable()
class ContactInput {
  const ContactInput({
    required this.lastName,
    this.active,
    this.addressForm,
    this.emails,
    this.firstName,
    this.jobTitle,
    this.language,
    this.notes,
    this.phones,
    this.portalAccess,
    this.portalScope,
    this.roles,
    this.title,
  });
  
  factory ContactInput.fromJson(Map<String, Object?> json) => _$ContactInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;

  /// formal | informal.
  @JsonKey(includeIfNull: false,name: 'address_form')
  final String? addressForm;

  /// The first one is the primary address.
  @JsonKey(includeIfNull: false)
  final List<String>? emails;
  @JsonKey(includeIfNull: false,name: 'first_name')
  final String? firstName;
  @JsonKey(includeIfNull: false,name: 'job_title')
  final String? jobTitle;

  /// nl | fr | en | de | es; null = same as the customer.
  @JsonKey(includeIfNull: false)
  final String? language;
  @JsonKey(name: 'last_name')
  final String lastName;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false)
  final List<PhoneInput>? phones;
  @JsonKey(includeIfNull: false,name: 'portal_access')
  final bool? portalAccess;

  /// own | customer
  @JsonKey(includeIfNull: false,name: 'portal_scope')
  final String? portalScope;
  @JsonKey(includeIfNull: false)
  final List<String>? roles;

  /// mr | ms | none — used in the salutation.
  @JsonKey(includeIfNull: false)
  final String? title;

  Map<String, Object?> toJson() => _$ContactInputToJson(this);
}
