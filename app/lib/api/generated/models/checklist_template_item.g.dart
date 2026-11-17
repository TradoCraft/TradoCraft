// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_template_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChecklistTemplateItem _$ChecklistTemplateItemFromJson(
  Map<String, dynamic> json,
) => ChecklistTemplateItem(
  description: json['description'] as String,
  id: json['id'] as String,
  position: (json['position'] as num).toInt(),
);

Map<String, dynamic> _$ChecklistTemplateItemToJson(
  ChecklistTemplateItem instance,
) => <String, dynamic>{
  'description': instance.description,
  'id': instance.id,
  'position': instance.position,
};
