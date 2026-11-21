// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mail_merge_message.g.dart';

@JsonSerializable()
class MailMergeMessage {
  const MailMergeMessage({
    required this.body,
    required this.subject,
  });
  
  factory MailMergeMessage.fromJson(Map<String, Object?> json) => _$MailMergeMessageFromJson(json);
  
  final String body;
  final String subject;

  Map<String, Object?> toJson() => _$MailMergeMessageToJson(this);
}
