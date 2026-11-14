// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'todo_link_kind.dart';

part 'todo_patch.g.dart';

@JsonSerializable()
class TodoPatch {
  const TodoPatch({
    this.assigneeId,
    this.clearAssignee,
    this.clearDueDate,
    this.clearLink,
    this.dueDate,
    this.linkId,
    this.linkKind,
    this.linkLabel,
    this.linkLocation,
    this.makeRoot,
    this.notes,
    this.parentId,
    this.position,
    this.title,
  });
  
  factory TodoPatch.fromJson(Map<String, Object?> json) => _$TodoPatchFromJson(json);
  
  /// Owner only; cascades to the sub-items.
  @JsonKey(includeIfNull: false,name: 'assignee_id')
  final String? assigneeId;
  @JsonKey(includeIfNull: false,name: 'clear_assignee')
  final bool? clearAssignee;
  @JsonKey(includeIfNull: false,name: 'clear_due_date')
  final bool? clearDueDate;
  @JsonKey(includeIfNull: false,name: 'clear_link')
  final bool? clearLink;
  @JsonKey(includeIfNull: false,name: 'due_date')
  final DateTime? dueDate;
  @JsonKey(includeIfNull: false,name: 'link_id')
  final String? linkId;
  @JsonKey(includeIfNull: false,name: 'link_kind')
  final TodoLinkKind? linkKind;
  @JsonKey(includeIfNull: false,name: 'link_label')
  final String? linkLabel;
  @JsonKey(includeIfNull: false,name: 'link_location')
  final String? linkLocation;

  /// Moves a sub-item up to be a root item.
  @JsonKey(includeIfNull: false,name: 'make_root')
  final bool? makeRoot;
  @JsonKey(includeIfNull: false)
  final String? notes;

  /// Moves a root item (without sub-items) under another root item of the same owner.
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;
  @JsonKey(includeIfNull: false)
  final int? position;
  @JsonKey(includeIfNull: false)
  final String? title;

  Map<String, Object?> toJson() => _$TodoPatchToJson(this);
}
