// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baseline_item_update.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BaselineItemUpdate _$BaselineItemUpdateFromJson(Map<String, dynamic> json) =>
    BaselineItemUpdate(
      name: json['name'] as String?,
      parentId: json['parent_id'] as String?,
      quantity: (json['quantity'] as num?)?.toInt(),
      sortOrder: (json['sort_order'] as num?)?.toInt(),
      values: json['values'],
    );

Map<String, dynamic> _$BaselineItemUpdateToJson(BaselineItemUpdate instance) =>
    <String, dynamic>{
      'name': ?instance.name,
      'parent_id': ?instance.parentId,
      'quantity': ?instance.quantity,
      'sort_order': ?instance.sortOrder,
      'values': ?instance.values,
    };
