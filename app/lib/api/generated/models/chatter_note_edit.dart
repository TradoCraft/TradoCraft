// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'chatter_note_edit.g.dart';

/// A new text for an own, recent note. Files cannot be added to a note afterwards.
@JsonSerializable()
class ChatterNoteEdit {
  const ChatterNoteEdit({
    required this.body,
  });
  
  factory ChatterNoteEdit.fromJson(Map<String, Object?> json) => _$ChatterNoteEditFromJson(json);
  
  final String body;

  Map<String, Object?> toJson() => _$ChatterNoteEditToJson(this);
}
