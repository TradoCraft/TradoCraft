// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'mail_merge_contact.dart';

part 'mail_merge_recipient.g.dart';

@JsonSerializable()
class MailMergeRecipient {
  const MailMergeRecipient({
    required this.contacts,
    required this.customerId,
    required this.customerName,
    required this.issues,
    required this.language,
    this.body,
    this.contactId,
    this.email,
    this.footer,
    this.pdf,
    this.subject,
  });
  
  factory MailMergeRecipient.fromJson(Map<String, Object?> json) => _$MailMergeRecipientFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? body;
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  final List<MailMergeContact> contacts;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(includeIfNull: false)
  final String? email;

  /// The unsubscribe footer appended below the body when the mail is queued; the link in the.
  /// preview is a placeholder, each delivery gets its own.
  @JsonKey(includeIfNull: false)
  final String? footer;
  final List<String> issues;
  final String language;
  @JsonKey(includeIfNull: false)
  final String? pdf;
  @JsonKey(includeIfNull: false)
  final String? subject;

  Map<String, Object?> toJson() => _$MailMergeRecipientToJson(this);
}
