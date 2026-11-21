// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'mail_merge_message.dart';

part 'mail_merge_draft.g.dart';

@JsonSerializable()
class MailMergeDraft {
  const MailMergeDraft({
    required this.documentId,
    required this.messages,
    required this.revision,
    this.recipients,
  });

  factory MailMergeDraft.fromJson(Map<String, Object?> json) => _$MailMergeDraftFromJson(json);

  @JsonKey(name: 'document_id')
  final String documentId;
  final Map<String, MailMergeMessage> messages;
  @JsonKey(includeIfNull: false)
  final Map<String, String>? recipients;
  final int revision;

  Map<String, Object?> toJson() => _$MailMergeDraftToJson(this);
}
