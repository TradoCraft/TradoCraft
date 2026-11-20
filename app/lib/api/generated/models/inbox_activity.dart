// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'inbox_activity.g.dart';

@JsonSerializable()
class InboxActivity {
  const InboxActivity({
    required this.dueDate,
    required this.id,
    required this.kind,
    required this.overdue,
    required this.recordId,
    required this.recordKind,
    required this.summary,
    this.label,
  });
  
  factory InboxActivity.fromJson(Map<String, Object?> json) => _$InboxActivityFromJson(json);
  
  @JsonKey(name: 'due_date')
  final DateTime dueDate;
  final String id;
  final String kind;
  @JsonKey(includeIfNull: false)
  final String? label;
  final bool overdue;
  @JsonKey(name: 'record_id')
  final String recordId;
  @JsonKey(name: 'record_kind')
  final String recordKind;
  final String summary;

  Map<String, Object?> toJson() => _$InboxActivityToJson(this);
}
