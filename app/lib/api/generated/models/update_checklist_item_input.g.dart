// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_checklist_item_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateChecklistItemInput _$UpdateChecklistItemInputFromJson(
  Map<String, dynamic> json,
) => UpdateChecklistItemInput(
  description: json['description'] as String?,
  done: json['done'] as bool?,
  position: (json['position'] as num?)?.toInt(),
);

Map<String, dynamic> _$UpdateChecklistItemInputToJson(
  UpdateChecklistItemInput instance,
) => <String, dynamic>{
  'description': ?instance.description,
  'done': ?instance.done,
  'position': ?instance.position,
};
