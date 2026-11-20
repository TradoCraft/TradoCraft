// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'activity.g.dart';

@JsonSerializable()
class Activity {
  const Activity({
    required this.assigneeId,
    required this.assigneeName,
    required this.createdAt,
    required this.createdBy,
    required this.dueDate,
    required this.id,
    required this.kind,
    required this.note,
    required this.overdue,
    required this.summary,
  });
  
  factory Activity.fromJson(Map<String, Object?> json) => _$ActivityFromJson(json);
  
  @JsonKey(name: 'assignee_id')
  final String assigneeId;
  @JsonKey(name: 'assignee_name')
  final String assigneeName;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'created_by')
  final String createdBy;
  @JsonKey(name: 'due_date')
  final DateTime dueDate;
  final String id;
  final String kind;
  final String note;

  /// Whether the due date is before today.
  final bool overdue;
  final String summary;

  Map<String, Object?> toJson() => _$ActivityToJson(this);
}
