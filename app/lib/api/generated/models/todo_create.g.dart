// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_create.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TodoCreate _$TodoCreateFromJson(Map<String, dynamic> json) => TodoCreate(
  title: json['title'] as String,
  assigneeId: json['assignee_id'] as String?,
  clientId: json['client_id'] as String?,
  dueDate: json['due_date'] == null
      ? null
      : DateTime.parse(json['due_date'] as String),
  linkId: json['link_id'] as String?,
  linkKind: json['link_kind'] == null
      ? null
      : TodoLinkKind.fromJson(json['link_kind'] as String),
  linkLabel: json['link_label'] as String?,
  linkLocation: json['link_location'] as String?,
  notes: json['notes'] as String?,
  parentId: json['parent_id'] as String?,
  position: (json['position'] as num?)?.toInt(),
);

Map<String, dynamic> _$TodoCreateToJson(TodoCreate instance) =>
    <String, dynamic>{
      'assignee_id': ?instance.assigneeId,
      'client_id': ?instance.clientId,
      'due_date': ?instance.dueDate?.toIso8601String(),
      'link_id': ?instance.linkId,
      'link_kind': ?instance.linkKind,
      'link_label': ?instance.linkLabel,
      'link_location': ?instance.linkLocation,
      'notes': ?instance.notes,
      'parent_id': ?instance.parentId,
      'position': ?instance.position,
      'title': instance.title,
    };
