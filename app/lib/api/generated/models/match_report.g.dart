// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_report.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MatchReport _$MatchReportFromJson(Map<String, dynamic> json) => MatchReport(
  lines: (json['lines'] as List<dynamic>)
      .map((e) => LineMatch.fromJson(e as Map<String, dynamic>))
      .toList(),
  matched: json['matched'] as bool,
  priceTolerancePct: json['price_tolerance_pct'] as String,
  quantityTolerancePct: json['quantity_tolerance_pct'] as String,
);

Map<String, dynamic> _$MatchReportToJson(MatchReport instance) =>
    <String, dynamic>{
      'lines': instance.lines,
      'matched': instance.matched,
      'price_tolerance_pct': instance.priceTolerancePct,
      'quantity_tolerance_pct': instance.quantityTolerancePct,
    };
