// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'time_entry.dart';

part 'time_entries.g.dart';

@JsonSerializable()
class TimeEntries {
  const TimeEntries({
    required this.billableMinutes,
    required this.items,
    required this.totalMinutes,
  });
  
  factory TimeEntries.fromJson(Map<String, Object?> json) => _$TimeEntriesFromJson(json);
  
  @JsonKey(name: 'billable_minutes')
  final int billableMinutes;
  final List<TimeEntry> items;
  @JsonKey(name: 'total_minutes')
  final int totalMinutes;

  Map<String, Object?> toJson() => _$TimeEntriesToJson(this);
}
