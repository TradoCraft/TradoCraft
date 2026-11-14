// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reply_input.g.dart';

@JsonSerializable()
class ReplyInput {
  const ReplyInput({
    required this.body,
    this.attachmentIds,
    this.cc,
    this.status,
    this.subject,
    this.to,
  });
  
  factory ReplyInput.fromJson(Map<String, Object?> json) => _$ReplyInputFromJson(json);
  
  /// Files uploaded to the ticket (`POST /tickets/{id}/attachments`) to send with the e-mail.
  @JsonKey(includeIfNull: false,name: 'attachment_ids')
  final List<String>? attachmentIds;
  final String body;
  @JsonKey(includeIfNull: false)
  final List<String>? cc;

  /// New ticket status; defaults to pending_customer.
  @JsonKey(includeIfNull: false)
  final String? status;

  /// Defaults to "Re: <ticket subject>". The ticket tag is always added.
  @JsonKey(includeIfNull: false)
  final String? subject;

  /// Defaults to the ticket's contact e-mail.
  @JsonKey(includeIfNull: false)
  final List<String>? to;

  Map<String, Object?> toJson() => _$ReplyInputToJson(this);
}
