// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'time_entry.g.dart';

@JsonSerializable()
class TimeEntry {
  const TimeEntry({
    required this.billable,
    required this.createdAt,
    required this.id,
    required this.minutes,
    required this.note,
    required this.userId,
    required this.userName,
  });
  
  factory TimeEntry.fromJson(Map<String, Object?> json) => _$TimeEntryFromJson(json);
  
  final bool billable;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  final int minutes;
  final String note;
  @JsonKey(name: 'user_id')
  final String userId;
  @JsonKey(name: 'user_name')
  final String userName;

  Map<String, Object?> toJson() => _$TimeEntryToJson(this);
}
