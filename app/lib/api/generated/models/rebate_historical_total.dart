// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_historical_total.g.dart';

@JsonSerializable()
class RebateHistoricalTotal {
  const RebateHistoricalTotal({
    required this.customerId,
    required this.cutoff,
    required this.eligibleSales,
    required this.year,
  });
  
  factory RebateHistoricalTotal.fromJson(Map<String, Object?> json) => _$RebateHistoricalTotalFromJson(json);
  
  @JsonKey(name: 'customer_id')
  final String customerId;
  final DateTime cutoff;
  @JsonKey(name: 'eligible_sales')
  final String eligibleSales;
  final int year;

  Map<String, Object?> toJson() => _$RebateHistoricalTotalToJson(this);
}
