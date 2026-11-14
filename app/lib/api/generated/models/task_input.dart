// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'task_input.g.dart';

@JsonSerializable()
class TaskInput {
  const TaskInput({
    required this.description,
    this.clientId,
  });
  
  factory TaskInput.fromJson(Map<String, Object?> json) => _$TaskInputFromJson(json);
  
  /// Chosen by the client: sending the same id again returns the first task instead of adding a.
  /// second one (offline retries). The same id with another description is a 409.
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;
  final String description;

  Map<String, Object?> toJson() => _$TaskInputToJson(this);
}
