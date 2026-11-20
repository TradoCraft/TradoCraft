// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Activity _$ActivityFromJson(Map<String, dynamic> json) => Activity(
  assigneeId: json['assignee_id'] as String,
  assigneeName: json['assignee_name'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  createdBy: json['created_by'] as String,
  dueDate: DateTime.parse(json['due_date'] as String),
  id: json['id'] as String,
  kind: json['kind'] as String,
  note: json['note'] as String,
  overdue: json['overdue'] as bool,
  summary: json['summary'] as String,
);

Map<String, dynamic> _$ActivityToJson(Activity instance) => <String, dynamic>{
  'assignee_id': instance.assigneeId,
  'assignee_name': instance.assigneeName,
  'created_at': instance.createdAt.toIso8601String(),
  'created_by': instance.createdBy,
  'due_date': instance.dueDate.toIso8601String(),
  'id': instance.id,
  'kind': instance.kind,
  'note': instance.note,
  'overdue': instance.overdue,
  'summary': instance.summary,
};
