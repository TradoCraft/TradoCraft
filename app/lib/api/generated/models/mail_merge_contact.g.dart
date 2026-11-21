// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mail_merge_contact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MailMergeContact _$MailMergeContactFromJson(Map<String, dynamic> json) =>
    MailMergeContact(
      customerId: json['customer_id'] as String,
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      language: json['language'] as String?,
    );

Map<String, dynamic> _$MailMergeContactToJson(MailMergeContact instance) =>
    <String, dynamic>{
      'customer_id': instance.customerId,
      'email': ?instance.email,
      'id': instance.id,
      'language': ?instance.language,
      'name': instance.name,
    };
