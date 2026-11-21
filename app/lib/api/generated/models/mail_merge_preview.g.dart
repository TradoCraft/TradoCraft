// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mail_merge_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MailMergePreview _$MailMergePreviewFromJson(Map<String, dynamic> json) =>
    MailMergePreview(
      audience: (json['audience'] as List<dynamic>)
          .map((e) => MailMergeRecipient.fromJson(e as Map<String, dynamic>))
          .toList(),
      approvalId: json['approval_id'] as String?,
      draft: json['draft'] == null
          ? null
          : MailMergeDraft.fromJson(json['draft'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$MailMergePreviewToJson(MailMergePreview instance) =>
    <String, dynamic>{
      'approval_id': ?instance.approvalId,
      'audience': instance.audience,
      'draft': ?instance.draft,
    };
