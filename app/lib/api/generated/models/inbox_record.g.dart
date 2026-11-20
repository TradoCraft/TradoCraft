// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InboxRecord _$InboxRecordFromJson(Map<String, dynamic> json) => InboxRecord(
  lastAt: DateTime.parse(json['last_at'] as String),
  recordId: json['record_id'] as String,
  recordKind: json['record_kind'] as String,
  unread: (json['unread'] as num).toInt(),
  label: json['label'] as String?,
);

Map<String, dynamic> _$InboxRecordToJson(InboxRecord instance) =>
    <String, dynamic>{
      'label': ?instance.label,
      'last_at': instance.lastAt.toIso8601String(),
      'record_id': instance.recordId,
      'record_kind': instance.recordKind,
      'unread': instance.unread,
    };
