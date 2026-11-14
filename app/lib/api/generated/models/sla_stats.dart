// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'sla_stats.g.dart';

@JsonSerializable()
class SlaStats {
  const SlaStats({
    required this.breached,
    required this.compliant,
    required this.tickets,
    this.compliancePercent,
  });
  
  factory SlaStats.fromJson(Map<String, Object?> json) => _$SlaStatsFromJson(json);
  
  final int breached;

  /// Share of tickets that did not breach, 0-100.
  @JsonKey(includeIfNull: false,name: 'compliance_percent')
  final double? compliancePercent;
  final int compliant;

  /// Tickets with a service level that were created in the period.
  final int tickets;

  Map<String, Object?> toJson() => _$SlaStatsToJson(this);
}
