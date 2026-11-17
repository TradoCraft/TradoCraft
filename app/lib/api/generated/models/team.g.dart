// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Team _$TeamFromJson(Map<String, dynamic> json) => Team(
  active: json['active'] as bool,
  createdAt: DateTime.parse(json['created_at'] as String),
  id: json['id'] as String,
  members: (json['members'] as List<dynamic>)
      .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
      .toList(),
  name: json['name'] as String,
  requireChecklistDone: json['require_checklist_done'] as bool,
);

Map<String, dynamic> _$TeamToJson(Team instance) => <String, dynamic>{
  'active': instance.active,
  'created_at': instance.createdAt.toIso8601String(),
  'id': instance.id,
  'members': instance.members,
  'name': instance.name,
  'require_checklist_done': instance.requireChecklistDone,
};
