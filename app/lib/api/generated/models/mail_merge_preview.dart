// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'mail_merge_draft.dart';
import 'mail_merge_recipient.dart';

part 'mail_merge_preview.g.dart';

@JsonSerializable()
class MailMergePreview {
  const MailMergePreview({
    required this.audience,
    this.approvalId,
    this.draft,
  });
  
  factory MailMergePreview.fromJson(Map<String, Object?> json) => _$MailMergePreviewFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'approval_id')
  final String? approvalId;
  final List<MailMergeRecipient> audience;
  @JsonKey(includeIfNull: false)
  final MailMergeDraft? draft;

  Map<String, Object?> toJson() => _$MailMergePreviewToJson(this);
}
