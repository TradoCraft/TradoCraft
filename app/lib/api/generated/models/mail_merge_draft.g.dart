// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mail_merge_draft.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MailMergeDraft _$MailMergeDraftFromJson(Map<String, dynamic> json) =>
    MailMergeDraft(
      documentId: json['document_id'] as String,
      messages: (json['messages'] as Map<String, dynamic>).map(
        (k, e) =>
            MapEntry(k, MailMergeMessage.fromJson(e as Map<String, dynamic>)),
      ),
      revision: (json['revision'] as num).toInt(),
      recipients: (json['recipients'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
    );

Map<String, dynamic> _$MailMergeDraftToJson(MailMergeDraft instance) =>
    <String, dynamic>{
      'document_id': instance.documentId,
      'messages': instance.messages,
      'recipients': ?instance.recipients,
      'revision': instance.revision,
    };
