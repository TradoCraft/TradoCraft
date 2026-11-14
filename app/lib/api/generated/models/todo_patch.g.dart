// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_patch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TodoPatch _$TodoPatchFromJson(Map<String, dynamic> json) => TodoPatch(
  assigneeId: json['assignee_id'] as String?,
  clearAssignee: json['clear_assignee'] as bool?,
  clearDueDate: json['clear_due_date'] as bool?,
  clearLink: json['clear_link'] as bool?,
  dueDate: json['due_date'] == null
      ? null
      : DateTime.parse(json['due_date'] as String),
  linkId: json['link_id'] as String?,
  linkKind: json['link_kind'] == null
      ? null
      : TodoLinkKind.fromJson(json['link_kind'] as String),
  linkLabel: json['link_label'] as String?,
  linkLocation: json['link_location'] as String?,
  makeRoot: json['make_root'] as bool?,
  notes: json['notes'] as String?,
  parentId: json['parent_id'] as String?,
  position: (json['position'] as num?)?.toInt(),
  title: json['title'] as String?,
);

Map<String, dynamic> _$TodoPatchToJson(TodoPatch instance) => <String, dynamic>{
  'assignee_id': ?instance.assigneeId,
  'clear_assignee': ?instance.clearAssignee,
  'clear_due_date': ?instance.clearDueDate,
  'clear_link': ?instance.clearLink,
  'due_date': ?instance.dueDate?.toIso8601String(),
  'link_id': ?instance.linkId,
  'link_kind': ?instance.linkKind,
  'link_label': ?instance.linkLabel,
  'link_location': ?instance.linkLocation,
  'make_root': ?instance.makeRoot,
  'notes': ?instance.notes,
  'parent_id': ?instance.parentId,
  'position': ?instance.position,
  'title': ?instance.title,
};
