// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'checklist_template_item_input.dart';

part 'checklist_template_input.g.dart';

@JsonSerializable()
class ChecklistTemplateInput {
  const ChecklistTemplateInput({
    required this.name,
    this.active,
    this.category,
    this.items,
    this.teamId,
  });
  
  factory ChecklistTemplateInput.fromJson(Map<String, Object?> json) => _$ChecklistTemplateInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false)
  final String? category;
  @JsonKey(includeIfNull: false)
  final List<ChecklistTemplateItemInput>? items;
  final String name;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;

  Map<String, Object?> toJson() => _$ChecklistTemplateInputToJson(this);
}
