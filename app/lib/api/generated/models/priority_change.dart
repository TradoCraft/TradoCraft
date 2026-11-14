// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'priority_change.g.dart';

@JsonSerializable()
class PriorityChange {
  const PriorityChange({
    required this.changedAt,
    required this.changedBy,
    required this.changedByName,
    required this.id,
    required this.newPriority,
    required this.oldPriority,
    required this.reason,
  });
  
  factory PriorityChange.fromJson(Map<String, Object?> json) => _$PriorityChangeFromJson(json);
  
  @JsonKey(name: 'changed_at')
  final DateTime changedAt;
  @JsonKey(name: 'changed_by')
  final String changedBy;
  @JsonKey(name: 'changed_by_name')
  final String changedByName;
  final String id;
  @JsonKey(name: 'new_priority')
  final String newPriority;
  @JsonKey(name: 'old_priority')
  final String oldPriority;
  final String reason;

  Map<String, Object?> toJson() => _$PriorityChangeToJson(this);
}
