// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'package_event.g.dart';

@JsonSerializable()
class PackageEvent {
  const PackageEvent({
    required this.actorName,
    required this.createdAt,
    required this.id,
    required this.kind,
    required this.note,
    this.fromStatus,
    this.repairId,
    this.repairNumber,
    this.toStatus,
  });
  
  factory PackageEvent.fromJson(Map<String, Object?> json) => _$PackageEventFromJson(json);
  
  @JsonKey(name: 'actor_name')
  final String actorName;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false,name: 'from_status')
  final String? fromStatus;
  final String id;

  /// registered | status | note | photo | linked | unlinked
  final String kind;
  final String note;
  @JsonKey(includeIfNull: false,name: 'repair_id')
  final String? repairId;
  @JsonKey(includeIfNull: false,name: 'repair_number')
  final String? repairNumber;
  @JsonKey(includeIfNull: false,name: 'to_status')
  final String? toStatus;

  Map<String, Object?> toJson() => _$PackageEventToJson(this);
}
