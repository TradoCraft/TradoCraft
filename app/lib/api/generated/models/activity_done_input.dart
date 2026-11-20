// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'activity_done_input.g.dart';

@JsonSerializable()
class ActivityDoneInput {
  const ActivityDoneInput({
    this.note,
  });
  
  factory ActivityDoneInput.fromJson(Map<String, Object?> json) => _$ActivityDoneInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? note;

  Map<String, Object?> toJson() => _$ActivityDoneInputToJson(this);
}
