// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'thread_item.g.dart';

/// One entry of the thread: a note or a change message.
@JsonSerializable()
class ThreadItem {
  const ThreadItem({
    required this.body,
    required this.changes,
    required this.createdAt,
    required this.editable,
    required this.id,
    required this.kind,
    this.authorId,
    this.authorName,
    this.editedAt,
  });
  
  factory ThreadItem.fromJson(Map<String, Object?> json) => _$ThreadItemFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'author_id')
  final String? authorId;
  @JsonKey(includeIfNull: false,name: 'author_name')
  final String? authorName;
  final String body;

  /// The tracked fields of a change message: `[{"field", "from", "to"}]`.
  final dynamic changes;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// Whether the caller may still edit or delete it (own note, within 15 minutes).
  final bool editable;
  @JsonKey(includeIfNull: false,name: 'edited_at')
  final DateTime? editedAt;

  /// Increases with time; the cursor for the next (older) page.
  final String id;

  /// `note` | `system`
  final String kind;

  Map<String, Object?> toJson() => _$ThreadItemToJson(this);
}
