// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'note_input.g.dart';

@JsonSerializable()
class NoteInput {
  const NoteInput({
    required this.body,
    this.attachmentIds,
    this.status,
  });
  
  factory NoteInput.fromJson(Map<String, Object?> json) => _$NoteInputFromJson(json);
  
  /// Files uploaded to the ticket (`POST /tickets/{id}/attachments`) to attach to this note.
  @JsonKey(includeIfNull: false,name: 'attachment_ids')
  final List<String>? attachmentIds;
  final String body;

  /// New ticket status; unchanged when omitted.
  @JsonKey(includeIfNull: false)
  final String? status;

  Map<String, Object?> toJson() => _$NoteInputToJson(this);
}
