// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'line_match.dart';

part 'match_report.g.dart';

/// Evaluated invoice.
@JsonSerializable()
class MatchReport {
  const MatchReport({
    required this.lines,
    required this.matched,
    required this.priceTolerancePct,
    required this.quantityTolerancePct,
  });
  
  factory MatchReport.fromJson(Map<String, Object?> json) => _$MatchReportFromJson(json);
  
  /// One entry per invoice line, in line order.
  final List<LineMatch> lines;

  /// True only when there is at least one line and every line is ok.
  final bool matched;

  /// Price tolerance used, percent.
  @JsonKey(name: 'price_tolerance_pct')
  final String priceTolerancePct;

  /// Quantity tolerance used, percent.
  @JsonKey(name: 'quantity_tolerance_pct')
  final String quantityTolerancePct;

  Map<String, Object?> toJson() => _$MatchReportToJson(this);
}
