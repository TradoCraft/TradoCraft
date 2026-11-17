// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TeamInput _$TeamInputFromJson(Map<String, dynamic> json) => TeamInput(
  name: json['name'] as String,
  active: json['active'] as bool?,
  members: (json['members'] as List<dynamic>?)
      ?.map((e) => MemberInput.fromJson(e as Map<String, dynamic>))
      .toList(),
  requireChecklistDone: json['require_checklist_done'] as bool?,
);

Map<String, dynamic> _$TeamInputToJson(TeamInput instance) => <String, dynamic>{
  'active': ?instance.active,
  'members': ?instance.members,
  'name': instance.name,
  'require_checklist_done': ?instance.requireChecklistDone,
};
