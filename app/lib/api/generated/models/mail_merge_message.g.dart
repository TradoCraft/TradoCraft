// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mail_merge_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MailMergeMessage _$MailMergeMessageFromJson(Map<String, dynamic> json) =>
    MailMergeMessage(
      body: json['body'] as String,
      subject: json['subject'] as String,
    );

Map<String, dynamic> _$MailMergeMessageToJson(MailMergeMessage instance) =>
    <String, dynamic>{'body': instance.body, 'subject': instance.subject};
