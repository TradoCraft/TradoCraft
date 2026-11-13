// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TodoItem _$TodoItemFromJson(Map<String, dynamic> json) => TodoItem(
  createdAt: DateTime.parse(json['created_at'] as String),
  createdBy: json['created_by'] as String,
  done: json['done'] as bool,
  id: json['id'] as String,
  mine: json['mine'] as bool,
  notes: json['notes'] as String,
  ownerId: json['owner_id'] as String,
  ownerName: json['owner_name'] as String,
  position: (json['position'] as num).toInt(),
  title: json['title'] as String,
  updatedAt: DateTime.parse(json['updated_at'] as String),
  assigneeId: json['assignee_id'] as String?,
  assigneeName: json['assignee_name'] as String?,
  clientId: json['client_id'] as String?,
  doneAt: json['done_at'] == null
      ? null
      : DateTime.parse(json['done_at'] as String),
  doneBy: json['done_by'] as String?,
  dueDate: json['due_date'] == null
      ? null
      : DateTime.parse(json['due_date'] as String),
  linkId: json['link_id'] as String?,
  linkKind: json['link_kind'] == null
      ? null
      : TodoLinkKind.fromJson(json['link_kind'] as String),
  linkLabel: json['link_label'] as String?,
  linkLocation: json['link_location'] as String?,
  parentId: json['parent_id'] as String?,
);

Map<String, dynamic> _$TodoItemToJson(TodoItem instance) => <String, dynamic>{
  'assignee_id': ?instance.assigneeId,
  'assignee_name': ?instance.assigneeName,
  'client_id': ?instance.clientId,
  'created_at': instance.createdAt.toIso8601String(),
  'created_by': instance.createdBy,
  'done': instance.done,
  'done_at': ?instance.doneAt?.toIso8601String(),
  'done_by': ?instance.doneBy,
  'due_date': ?instance.dueDate?.toIso8601String(),
  'id': instance.id,
  'link_id': ?instance.linkId,
  'link_kind': ?instance.linkKind,
  'link_label': ?instance.linkLabel,
  'link_location': ?instance.linkLocation,
  'mine': instance.mine,
  'notes': instance.notes,
  'owner_id': instance.ownerId,
  'owner_name': instance.ownerName,
  'parent_id': ?instance.parentId,
  'position': instance.position,
  'title': instance.title,
  'updated_at': instance.updatedAt.toIso8601String(),
};
