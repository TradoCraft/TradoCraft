// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'entry_text.dart';

part 'entry_version.g.dart';

@JsonSerializable()
class EntryVersion {
  const EntryVersion({
    required this.editedAt,
    required this.texts,
    required this.version,
    this.editorId,
    this.editorName,
    this.restoredFrom,
  });
  
  factory EntryVersion.fromJson(Map<String, Object?> json) => _$EntryVersionFromJson(json);
  
  @JsonKey(name: 'edited_at')
  final DateTime editedAt;
  @JsonKey(includeIfNull: false,name: 'editor_id')
  final String? editorId;
  @JsonKey(includeIfNull: false,name: 'editor_name')
  final String? editorName;

  /// Set when this version was made by restoring an earlier one.
  @JsonKey(includeIfNull: false,name: 'restored_from')
  final int? restoredFrom;
  final List<EntryText> texts;
  final int version;

  Map<String, Object?> toJson() => _$EntryVersionToJson(this);
}
