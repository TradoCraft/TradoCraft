// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mail_merge_recipient.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MailMergeRecipient _$MailMergeRecipientFromJson(Map<String, dynamic> json) =>
    MailMergeRecipient(
      contacts: (json['contacts'] as List<dynamic>)
          .map((e) => MailMergeContact.fromJson(e as Map<String, dynamic>))
          .toList(),
      customerId: json['customer_id'] as String,
      customerName: json['customer_name'] as String,
      issues: (json['issues'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      language: json['language'] as String,
      body: json['body'] as String?,
      contactId: json['contact_id'] as String?,
      email: json['email'] as String?,
      pdf: json['pdf'] as String?,
      subject: json['subject'] as String?,
    );

Map<String, dynamic> _$MailMergeRecipientToJson(MailMergeRecipient instance) =>
    <String, dynamic>{
      'body': ?instance.body,
      'contact_id': ?instance.contactId,
      'contacts': instance.contacts,
      'customer_id': instance.customerId,
      'customer_name': instance.customerName,
      'email': ?instance.email,
      'issues': instance.issues,
      'language': instance.language,
      'pdf': ?instance.pdf,
      'subject': ?instance.subject,
    };
