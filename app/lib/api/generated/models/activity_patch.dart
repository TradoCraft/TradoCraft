// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'activity_kind.dart';

part 'activity_patch.g.dart';

/// Fields to change on an open activity; absent fields stay as they are.
@JsonSerializable()
class ActivityPatch {
  const ActivityPatch({
    this.assigneeId,
    this.dueDate,
    this.kind,
    this.note,
    this.summary,
  });
  
  factory ActivityPatch.fromJson(Map<String, Object?> json) => _$ActivityPatchFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'assignee_id')
  final String? assigneeId;

  /// `YYYY-MM-DD`; a full datetime is accepted and cut to its date.
  @JsonKey(includeIfNull: false,name: 'due_date')
  final DateTime? dueDate;
  @JsonKey(includeIfNull: false)
  final ActivityKind? kind;
  @JsonKey(includeIfNull: false)
  final String? note;
  @JsonKey(includeIfNull: false)
  final String? summary;

  Map<String, Object?> toJson() => _$ActivityPatchToJson(this);
}
