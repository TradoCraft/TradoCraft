// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'repair_event.g.dart';

@JsonSerializable()
class RepairEvent {
  const RepairEvent({
    required this.actorName,
    required this.createdAt,
    required this.id,
    required this.kind,
    required this.note,
    this.fromDepartment,
    this.fromStatus,
    this.toDepartment,
    this.toStatus,
  });
  
  factory RepairEvent.fromJson(Map<String, Object?> json) => _$RepairEventFromJson(json);
  
  @JsonKey(name: 'actor_name')
  final String actorName;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false,name: 'from_department')
  final String? fromDepartment;
  @JsonKey(includeIfNull: false,name: 'from_status')
  final String? fromStatus;
  final String id;

  /// created | status | routed | note | photo | package_linked | package_unlinked | findings | serial_unit |.
  /// warranty_auto | warranty_manual | warranty_void | warranty_void_removed.
  final String kind;
  final String note;
  @JsonKey(includeIfNull: false,name: 'to_department')
  final String? toDepartment;
  @JsonKey(includeIfNull: false,name: 'to_status')
  final String? toStatus;

  Map<String, Object?> toJson() => _$RepairEventToJson(this);
}
