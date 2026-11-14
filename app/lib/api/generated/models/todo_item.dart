// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'todo_link_kind.dart';

part 'todo_item.g.dart';

/// One to-do item. Lists are flat: build the tree from `parent_id`.
@JsonSerializable()
class TodoItem {
  const TodoItem({
    required this.createdAt,
    required this.createdBy,
    required this.done,
    required this.id,
    required this.mine,
    required this.notes,
    required this.ownerId,
    required this.ownerName,
    required this.position,
    required this.title,
    required this.updatedAt,
    this.assigneeId,
    this.assigneeName,
    this.clientId,
    this.doneAt,
    this.doneBy,
    this.dueDate,
    this.linkId,
    this.linkKind,
    this.linkLabel,
    this.linkLocation,
    this.parentId,
  });
  
  factory TodoItem.fromJson(Map<String, Object?> json) => _$TodoItemFromJson(json);
  
  /// The colleague the item is handed to; absent when it stays with the owner.
  @JsonKey(includeIfNull: false,name: 'assignee_id')
  final String? assigneeId;
  @JsonKey(includeIfNull: false,name: 'assignee_name')
  final String? assigneeName;
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'created_by')
  final String createdBy;
  final bool done;
  @JsonKey(includeIfNull: false,name: 'done_at')
  final DateTime? doneAt;
  @JsonKey(includeIfNull: false,name: 'done_by')
  final String? doneBy;
  @JsonKey(includeIfNull: false,name: 'due_date')
  final DateTime? dueDate;
  final String id;
  @JsonKey(includeIfNull: false,name: 'link_id')
  final String? linkId;
  @JsonKey(includeIfNull: false,name: 'link_kind')
  final TodoLinkKind? linkKind;

  /// What the linked record was called when it was linked. Absent when the caller may not read.
  /// records of that kind (the app then shows "Linked item").
  @JsonKey(includeIfNull: false,name: 'link_label')
  final String? linkLabel;

  /// Where the app jumps to for the linked record, e.g. `/quotations/<id>`.
  @JsonKey(includeIfNull: false,name: 'link_location')
  final String? linkLocation;

  /// Whether the caller is the owner (only the owner reassigns and deletes).
  final bool mine;
  final String notes;
  @JsonKey(name: 'owner_id')
  final String ownerId;
  @JsonKey(name: 'owner_name')
  final String ownerName;

  /// The root item this is a sub-item of; absent for a root item.
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;
  final int position;
  final String title;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$TodoItemToJson(this);
}
