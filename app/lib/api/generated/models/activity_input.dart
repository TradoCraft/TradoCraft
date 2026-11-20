// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'activity_kind.dart';

part 'activity_input.g.dart';

@JsonSerializable()
class ActivityInput {
  const ActivityInput({
    required this.assigneeId,
    required this.dueDate,
    required this.kind,
    required this.summary,
    this.clientId,
    this.note,
  });
  
  factory ActivityInput.fromJson(Map<String, Object?> json) => _$ActivityInputFromJson(json);
  
  @JsonKey(name: 'assignee_id')
  final String assigneeId;
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;

  /// `YYYY-MM-DD`; a full datetime (a Dart `DateTime`) is accepted and cut to its date.
  @JsonKey(name: 'due_date')
  final DateTime dueDate;
  final ActivityKind kind;
  @JsonKey(includeIfNull: false)
  final String? note;
  final String summary;

  Map<String, Object?> toJson() => _$ActivityInputToJson(this);
}
