// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baseline_item_type.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BaselineItemType _$BaselineItemTypeFromJson(Map<String, dynamic> json) =>
    BaselineItemType(
      active: json['active'] as bool,
      allowTopLevel: json['allow_top_level'] as bool,
      allowedParentCodes: (json['allowed_parent_codes'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      code: json['code'] as String,
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: (json['sort_order'] as num).toInt(),
    );

Map<String, dynamic> _$BaselineItemTypeToJson(BaselineItemType instance) =>
    <String, dynamic>{
      'active': instance.active,
      'allow_top_level': instance.allowTopLevel,
      'allowed_parent_codes': instance.allowedParentCodes,
      'code': instance.code,
      'id': instance.id,
      'name': instance.name,
      'sort_order': instance.sortOrder,
    };
