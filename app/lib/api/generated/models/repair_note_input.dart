// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'repair_note_input.g.dart';

@JsonSerializable()
class RepairNoteInput {
  const RepairNoteInput({
    required this.note,
  });
  
  factory RepairNoteInput.fromJson(Map<String, Object?> json) => _$RepairNoteInputFromJson(json);
  
  final String note;

  Map<String, Object?> toJson() => _$RepairNoteInputToJson(this);
}
