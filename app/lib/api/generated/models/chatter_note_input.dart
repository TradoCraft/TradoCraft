// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'chatter_note_input.g.dart';

@JsonSerializable()
class ChatterNoteInput {
  const ChatterNoteInput({
    required this.body,
    this.clientId,
  });
  
  factory ChatterNoteInput.fromJson(Map<String, Object?> json) => _$ChatterNoteInputFromJson(json);
  
  final String body;

  /// Chosen by the client so that a retried post does not post twice.
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;

  Map<String, Object?> toJson() => _$ChatterNoteInputToJson(this);
}
