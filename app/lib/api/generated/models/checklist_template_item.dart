// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'checklist_template_item.g.dart';

@JsonSerializable()
class ChecklistTemplateItem {
  const ChecklistTemplateItem({
    required this.description,
    required this.id,
    required this.position,
  });
  
  factory ChecklistTemplateItem.fromJson(Map<String, Object?> json) => _$ChecklistTemplateItemFromJson(json);
  
  final String description;
  final String id;
  final int position;

  Map<String, Object?> toJson() => _$ChecklistTemplateItemToJson(this);
}
