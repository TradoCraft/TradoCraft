// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_template_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChecklistTemplateInput _$ChecklistTemplateInputFromJson(
  Map<String, dynamic> json,
) => ChecklistTemplateInput(
  name: json['name'] as String,
  active: json['active'] as bool?,
  category: json['category'] as String?,
  items: (json['items'] as List<dynamic>?)
      ?.map(
        (e) => ChecklistTemplateItemInput.fromJson(e as Map<String, dynamic>),
      )
      .toList(),
  teamId: json['team_id'] as String?,
);

Map<String, dynamic> _$ChecklistTemplateInputToJson(
  ChecklistTemplateInput instance,
) => <String, dynamic>{
  'active': ?instance.active,
  'category': ?instance.category,
  'items': ?instance.items,
  'name': instance.name,
  'team_id': ?instance.teamId,
};
