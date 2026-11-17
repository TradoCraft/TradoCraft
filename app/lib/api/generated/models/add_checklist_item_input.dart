// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'add_checklist_item_input.g.dart';

@JsonSerializable()
class AddChecklistItemInput {
  const AddChecklistItemInput({
    required this.description,
  });
  
  factory AddChecklistItemInput.fromJson(Map<String, Object?> json) => _$AddChecklistItemInputFromJson(json);
  
  final String description;

  Map<String, Object?> toJson() => _$AddChecklistItemInputToJson(this);
}
