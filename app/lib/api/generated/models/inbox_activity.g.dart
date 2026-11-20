// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_activity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InboxActivity _$InboxActivityFromJson(Map<String, dynamic> json) =>
    InboxActivity(
      dueDate: DateTime.parse(json['due_date'] as String),
      id: json['id'] as String,
      kind: json['kind'] as String,
      overdue: json['overdue'] as bool,
      recordId: json['record_id'] as String,
      recordKind: json['record_kind'] as String,
      summary: json['summary'] as String,
      label: json['label'] as String?,
    );

Map<String, dynamic> _$InboxActivityToJson(InboxActivity instance) =>
    <String, dynamic>{
      'due_date': instance.dueDate.toIso8601String(),
      'id': instance.id,
      'kind': instance.kind,
      'label': ?instance.label,
      'overdue': instance.overdue,
      'record_id': instance.recordId,
      'record_kind': instance.recordKind,
      'summary': instance.summary,
    };
