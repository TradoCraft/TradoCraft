// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reorder_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReorderInput _$ReorderInputFromJson(Map<String, dynamic> json) => ReorderInput(
  ids: (json['ids'] as List<dynamic>).map((e) => e as String).toList(),
  parentId: json['parent_id'] as String?,
);

Map<String, dynamic> _$ReorderInputToJson(ReorderInput instance) =>
    <String, dynamic>{'ids': instance.ids, 'parent_id': ?instance.parentId};
