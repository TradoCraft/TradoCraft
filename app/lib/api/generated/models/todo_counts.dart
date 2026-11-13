// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'todo_counts.g.dart';

@JsonSerializable()
class TodoCounts {
  const TodoCounts({
    required this.dueToday,
    required this.open,
    required this.overdue,
  });
  
  factory TodoCounts.fromJson(Map<String, Object?> json) => _$TodoCountsFromJson(json);
  
  /// Open items on my plate that are due today.
  @JsonKey(name: 'due_today')
  final int dueToday;

  /// Open items on my plate, sub-items included.
  final int open;

  /// Open items on my plate that were due before today.
  final int overdue;

  Map<String, Object?> toJson() => _$TodoCountsToJson(this);
}
