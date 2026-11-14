// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'todo_link_kind.dart';

part 'todo_create.g.dart';

@JsonSerializable()
class TodoCreate {
  const TodoCreate({
    required this.title,
    this.assigneeId,
    this.clientId,
    this.dueDate,
    this.linkId,
    this.linkKind,
    this.linkLabel,
    this.linkLocation,
    this.notes,
    this.parentId,
    this.position,
  });

  factory TodoCreate.fromJson(Map<String, Object?> json) =>
      _$TodoCreateFromJson(json);

  /// Hands the item to a colleague. Not allowed for sub-items.
  @JsonKey(includeIfNull: false, name: 'assignee_id')
  final String? assigneeId;

  /// Chosen by the client; a repeated create with the same id returns the item that exists.
  @JsonKey(includeIfNull: false, name: 'client_id')
  final String? clientId;
  @JsonKey(includeIfNull: false, name: 'due_date')
  final DateTime? dueDate;
  @JsonKey(includeIfNull: false, name: 'link_id')
  final String? linkId;
  @JsonKey(includeIfNull: false, name: 'link_kind')
  final TodoLinkKind? linkKind;
  @JsonKey(includeIfNull: false, name: 'link_label')
  final String? linkLabel;
  @JsonKey(includeIfNull: false, name: 'link_location')
  final String? linkLocation;
  @JsonKey(includeIfNull: false)
  final String? notes;

  /// Makes this a sub-item of that root item; it then shares the parent's owner and assignee.
  @JsonKey(includeIfNull: false, name: 'parent_id')
  final String? parentId;

  /// Defaults to the end of its siblings.
  @JsonKey(includeIfNull: false)
  final int? position;
  final String title;

  Map<String, Object?> toJson() => _$TodoCreateToJson(this);
}
