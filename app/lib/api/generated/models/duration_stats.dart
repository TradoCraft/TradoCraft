// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'duration_stats.g.dart';

@JsonSerializable()
class DurationStats {
  const DurationStats({
    required this.count,
    this.averageMinutes,
    this.p90Minutes,
  });
  
  factory DurationStats.fromJson(Map<String, Object?> json) => _$DurationStatsFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'average_minutes')
  final double? averageMinutes;
  final int count;
  @JsonKey(includeIfNull: false,name: 'p90_minutes')
  final double? p90Minutes;

  Map<String, Object?> toJson() => _$DurationStatsToJson(this);
}
