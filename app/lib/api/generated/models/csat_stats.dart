// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'csat_stats.g.dart';

@JsonSerializable()
class CsatStats {
  const CsatStats({
    required this.bad,
    required this.good,
    required this.responses,
    this.averagePercent,
  });
  
  factory CsatStats.fromJson(Map<String, Object?> json) => _$CsatStatsFromJson(json);
  
  /// Average satisfaction: share of "good" ratings, 0-100.
  @JsonKey(includeIfNull: false,name: 'average_percent')
  final double? averagePercent;
  final int bad;
  final int good;
  final int responses;

  Map<String, Object?> toJson() => _$CsatStatsToJson(this);
}
