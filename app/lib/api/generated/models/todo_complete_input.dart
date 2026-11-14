// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'todo_complete_input.g.dart';

@JsonSerializable()
class TodoCompleteInput {
  const TodoCompleteInput({this.completeChildren});

  factory TodoCompleteInput.fromJson(Map<String, Object?> json) =>
      _$TodoCompleteInputFromJson(json);

  /// Also complete the open sub-items. Without it, completing an item that still has open.
  /// sub-items is refused with 409.
  @JsonKey(includeIfNull: false, name: 'complete_children')
  final bool? completeChildren;

  Map<String, Object?> toJson() => _$TodoCompleteInputToJson(this);
}
