// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baseline_item_type_update.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BaselineItemTypeUpdate _$BaselineItemTypeUpdateFromJson(
  Map<String, dynamic> json,
) => BaselineItemTypeUpdate(
  name: json['name'] as String,
  active: json['active'] as bool?,
  allowTopLevel: json['allow_top_level'] as bool?,
  allowedParentCodes: (json['allowed_parent_codes'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  sortOrder: (json['sort_order'] as num?)?.toInt(),
);

Map<String, dynamic> _$BaselineItemTypeUpdateToJson(
  BaselineItemTypeUpdate instance,
) => <String, dynamic>{
  'active': ?instance.active,
  'allow_top_level': ?instance.allowTopLevel,
  'allowed_parent_codes': ?instance.allowedParentCodes,
  'name': instance.name,
  'sort_order': ?instance.sortOrder,
};
