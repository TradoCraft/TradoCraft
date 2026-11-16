// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChecklistItem _$ChecklistItemFromJson(Map<String, dynamic> json) =>
    ChecklistItem(
      description: json['description'] as String,
      done: json['done'] as bool,
      id: json['id'] as String,
      position: (json['position'] as num).toInt(),
      ticketId: json['ticket_id'] as String,
      doneAt: json['done_at'] == null
          ? null
          : DateTime.parse(json['done_at'] as String),
      doneBy: json['done_by'] as String?,
      doneByName: json['done_by_name'] as String?,
      templateId: json['template_id'] as String?,
    );

Map<String, dynamic> _$ChecklistItemToJson(ChecklistItem instance) =>
    <String, dynamic>{
      'description': instance.description,
      'done': instance.done,
      'done_at': ?instance.doneAt?.toIso8601String(),
      'done_by': ?instance.doneBy,
      'done_by_name': ?instance.doneByName,
      'id': instance.id,
      'position': instance.position,
      'template_id': ?instance.templateId,
      'ticket_id': instance.ticketId,
    };
