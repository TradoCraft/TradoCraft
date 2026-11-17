// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'checklist_item.g.dart';

@JsonSerializable()
class ChecklistItem {
  const ChecklistItem({
    required this.description,
    required this.done,
    required this.id,
    required this.position,
    required this.ticketId,
    this.doneAt,
    this.doneBy,
    this.doneByName,
    this.templateId,
  });
  
  factory ChecklistItem.fromJson(Map<String, Object?> json) => _$ChecklistItemFromJson(json);
  
  final String description;
  final bool done;
  @JsonKey(includeIfNull: false,name: 'done_at')
  final DateTime? doneAt;
  @JsonKey(includeIfNull: false,name: 'done_by')
  final String? doneBy;
  @JsonKey(includeIfNull: false,name: 'done_by_name')
  final String? doneByName;
  final String id;
  final int position;
  @JsonKey(includeIfNull: false,name: 'template_id')
  final String? templateId;
  @JsonKey(name: 'ticket_id')
  final String ticketId;

  Map<String, Object?> toJson() => _$ChecklistItemToJson(this);
}
