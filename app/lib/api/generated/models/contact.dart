// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'contact_email.dart';
import 'contact_phone.dart';

part 'contact.g.dart';

@JsonSerializable()
class Contact {
  const Contact({
    required this.active,
    required this.addressForm,
    required this.createdAt,
    required this.customerCode,
    required this.customerId,
    required this.customerLanguage,
    required this.customerName,
    required this.effectiveLanguage,
    required this.emails,
    required this.firstName,
    required this.fullName,
    required this.greeting,
    required this.id,
    required this.jobTitle,
    required this.lastName,
    required this.notes,
    required this.phones,
    required this.portalAccess,
    required this.portalScope,
    required this.roles,
    required this.title,
    required this.updatedAt,
    this.language,
  });
  
  factory Contact.fromJson(Map<String, Object?> json) => _$ContactFromJson(json);
  
  final bool active;

  /// formal | informal
  @JsonKey(name: 'address_form')
  final String addressForm;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'customer_code')
  final String customerCode;
  @JsonKey(name: 'customer_id')
  final String customerId;

  /// The language of the customer (company level).
  @JsonKey(name: 'customer_language')
  final String customerLanguage;
  @JsonKey(name: 'customer_name')
  final String customerName;

  /// The language to write to this person in: their own, else the customer's.
  @JsonKey(name: 'effective_language')
  final String effectiveLanguage;
  final List<ContactEmail> emails;
  @JsonKey(name: 'first_name')
  final String firstName;
  @JsonKey(name: 'full_name')
  final String fullName;

  /// Ready-made salutation in the effective language and address form.
  final String greeting;
  final String id;
  @JsonKey(name: 'job_title')
  final String jobTitle;

  /// The person's own language; null means the same as the customer.
  @JsonKey(includeIfNull: false)
  final String? language;
  @JsonKey(name: 'last_name')
  final String lastName;
  final String notes;
  final List<ContactPhone> phones;
  @JsonKey(name: 'portal_access')
  final bool portalAccess;

  /// own | customer
  @JsonKey(name: 'portal_scope')
  final String portalScope;

  /// sales_contact | technical | purchasing | invoicing | management | quality | other
  final List<String> roles;

  /// mr | ms | none
  final String title;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ContactToJson(this);
}
