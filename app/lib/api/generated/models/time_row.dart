// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'time_row.g.dart';

@JsonSerializable()
class TimeRow {
  const TimeRow({
    required this.billableMinutes,
    required this.name,
    required this.nonBillableMinutes,
    required this.totalMinutes,
    required this.userId,
  });
  
  factory TimeRow.fromJson(Map<String, Object?> json) => _$TimeRowFromJson(json);
  
  @JsonKey(name: 'billable_minutes')
  final int billableMinutes;
  final String name;
  @JsonKey(name: 'non_billable_minutes')
  final int nonBillableMinutes;
  @JsonKey(name: 'total_minutes')
  final int totalMinutes;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$TimeRowToJson(this);
}
