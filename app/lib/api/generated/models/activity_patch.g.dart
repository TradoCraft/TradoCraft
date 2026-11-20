// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_patch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ActivityPatch _$ActivityPatchFromJson(Map<String, dynamic> json) =>
    ActivityPatch(
      assigneeId: json['assignee_id'] as String?,
      dueDate: json['due_date'] == null
          ? null
          : DateTime.parse(json['due_date'] as String),
      kind: json['kind'] == null
          ? null
          : ActivityKind.fromJson(json['kind'] as String),
      note: json['note'] as String?,
      summary: json['summary'] as String?,
    );

Map<String, dynamic> _$ActivityPatchToJson(ActivityPatch instance) =>
    <String, dynamic>{
      'assignee_id': ?instance.assigneeId,
      'due_date': ?instance.dueDate?.toIso8601String(),
      'kind': ?instance.kind,
      'note': ?instance.note,
      'summary': ?instance.summary,
    };
