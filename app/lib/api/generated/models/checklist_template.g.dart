// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChecklistTemplate _$ChecklistTemplateFromJson(Map<String, dynamic> json) =>
    ChecklistTemplate(
      active: json['active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      id: json['id'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => ChecklistTemplateItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      name: json['name'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      category: json['category'] as String?,
      teamId: json['team_id'] as String?,
      teamName: json['team_name'] as String?,
    );

Map<String, dynamic> _$ChecklistTemplateToJson(ChecklistTemplate instance) =>
    <String, dynamic>{
      'active': instance.active,
      'category': ?instance.category,
      'created_at': instance.createdAt.toIso8601String(),
      'id': instance.id,
      'items': instance.items,
      'name': instance.name,
      'team_id': ?instance.teamId,
      'team_name': ?instance.teamName,
      'updated_at': instance.updatedAt.toIso8601String(),
    };
