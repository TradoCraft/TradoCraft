// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'message_input.g.dart';

@JsonSerializable()
class MessageInput {
  const MessageInput({
    required this.body,
    this.attachmentIds,
  });
  
  factory MessageInput.fromJson(Map<String, Object?> json) => _$MessageInputFromJson(json);
  
  /// Files uploaded to the ticket (`POST /portal/tickets/{id}/attachments`) to send along.
  @JsonKey(includeIfNull: false,name: 'attachment_ids')
  final List<String>? attachmentIds;
  final String body;

  Map<String, Object?> toJson() => _$MessageInputToJson(this);
}
