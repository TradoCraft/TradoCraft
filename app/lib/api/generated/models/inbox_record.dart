// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'inbox_record.g.dart';

@JsonSerializable()
class InboxRecord {
  const InboxRecord({
    required this.lastAt,
    required this.recordId,
    required this.recordKind,
    required this.unread,
    this.label,
  });
  
  factory InboxRecord.fromJson(Map<String, Object?> json) => _$InboxRecordFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? label;
  @JsonKey(name: 'last_at')
  final DateTime lastAt;
  @JsonKey(name: 'record_id')
  final String recordId;
  @JsonKey(name: 'record_kind')
  final String recordKind;

  /// Messages by others since the caller last read the record.
  final int unread;

  Map<String, Object?> toJson() => _$InboxRecordToJson(this);
}
