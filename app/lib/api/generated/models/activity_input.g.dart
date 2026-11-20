// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ActivityInput _$ActivityInputFromJson(Map<String, dynamic> json) =>
    ActivityInput(
      assigneeId: json['assignee_id'] as String,
      dueDate: DateTime.parse(json['due_date'] as String),
      kind: ActivityKind.fromJson(json['kind'] as String),
      summary: json['summary'] as String,
      clientId: json['client_id'] as String?,
      note: json['note'] as String?,
    );

Map<String, dynamic> _$ActivityInputToJson(ActivityInput instance) =>
    <String, dynamic>{
      'assignee_id': instance.assigneeId,
      'client_id': ?instance.clientId,
      'due_date': instance.dueDate.toIso8601String(),
      'kind': instance.kind,
      'note': ?instance.note,
      'summary': instance.summary,
    };
