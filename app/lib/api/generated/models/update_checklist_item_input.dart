// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'update_checklist_item_input.g.dart';

@JsonSerializable()
class UpdateChecklistItemInput {
  const UpdateChecklistItemInput({
    this.description,
    this.done,
    this.position,
  });
  
  factory UpdateChecklistItemInput.fromJson(Map<String, Object?> json) => _$UpdateChecklistItemInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? description;
  @JsonKey(includeIfNull: false)
  final bool? done;
  @JsonKey(includeIfNull: false)
  final int? position;

  Map<String, Object?> toJson() => _$UpdateChecklistItemInputToJson(this);
}
