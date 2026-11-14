// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baseline_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BaselineItem _$BaselineItemFromJson(Map<String, dynamic> json) => BaselineItem(
  children: (json['children'] as List<dynamic>)
      .map((e) => BaselineItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  createdAt: DateTime.parse(json['created_at'] as String),
  id: json['id'] as String,
  quantity: (json['quantity'] as num).toInt(),
  sortOrder: (json['sort_order'] as num).toInt(),
  typeCode: json['type_code'] as String,
  updatedAt: DateTime.parse(json['updated_at'] as String),
  values: json['values'],
  name: json['name'] as String?,
  parentId: json['parent_id'] as String?,
);

Map<String, dynamic> _$BaselineItemToJson(BaselineItem instance) =>
    <String, dynamic>{
      'children': instance.children,
      'created_at': instance.createdAt.toIso8601String(),
      'id': instance.id,
      'name': ?instance.name,
      'parent_id': ?instance.parentId,
      'quantity': instance.quantity,
      'sort_order': instance.sortOrder,
      'type_code': instance.typeCode,
      'updated_at': instance.updatedAt.toIso8601String(),
      'values': instance.values,
    };
