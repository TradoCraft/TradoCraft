// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baseline_item_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BaselineItemInput _$BaselineItemInputFromJson(Map<String, dynamic> json) =>
    BaselineItemInput(
      typeCode: json['type_code'] as String,
      name: json['name'] as String?,
      parentId: json['parent_id'] as String?,
      quantity: (json['quantity'] as num?)?.toInt(),
      sortOrder: (json['sort_order'] as num?)?.toInt(),
      values: json['values'],
    );

Map<String, dynamic> _$BaselineItemInputToJson(BaselineItemInput instance) =>
    <String, dynamic>{
      'name': ?instance.name,
      'parent_id': ?instance.parentId,
      'quantity': ?instance.quantity,
      'sort_order': ?instance.sortOrder,
      'type_code': instance.typeCode,
      'values': ?instance.values,
    };
