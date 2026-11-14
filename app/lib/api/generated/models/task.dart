// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'task.g.dart';

@JsonSerializable()
class Task {
  const Task({
    required this.description,
    required this.done,
    required this.id,
    required this.position,
    this.doneAt,
    this.doneByName,
  });
  
  factory Task.fromJson(Map<String, Object?> json) => _$TaskFromJson(json);
  
  final String description;
  final bool done;
  @JsonKey(includeIfNull: false,name: 'done_at')
  final DateTime? doneAt;
  @JsonKey(includeIfNull: false,name: 'done_by_name')
  final String? doneByName;
  final String id;
  final int position;

  Map<String, Object?> toJson() => _$TaskToJson(this);
}
