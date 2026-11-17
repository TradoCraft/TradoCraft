// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'checklist_template_item.dart';

part 'checklist_template.g.dart';

@JsonSerializable()
class ChecklistTemplate {
  const ChecklistTemplate({
    required this.active,
    required this.createdAt,
    required this.id,
    required this.items,
    required this.name,
    required this.updatedAt,
    this.category,
    this.teamId,
    this.teamName,
  });
  
  factory ChecklistTemplate.fromJson(Map<String, Object?> json) => _$ChecklistTemplateFromJson(json);
  
  final bool active;
  @JsonKey(includeIfNull: false)
  final String? category;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  final List<ChecklistTemplateItem> items;
  final String name;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;
  @JsonKey(includeIfNull: false,name: 'team_name')
  final String? teamName;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ChecklistTemplateToJson(this);
}
