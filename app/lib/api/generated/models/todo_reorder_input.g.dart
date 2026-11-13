// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_reorder_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TodoReorderInput _$TodoReorderInputFromJson(Map<String, dynamic> json) =>
    TodoReorderInput(
      ids: (json['ids'] as List<dynamic>).map((e) => e as String).toList(),
      parentId: json['parent_id'] as String?,
    );

Map<String, dynamic> _$TodoReorderInputToJson(TodoReorderInput instance) =>
    <String, dynamic>{'ids': instance.ids, 'parent_id': ?instance.parentId};
