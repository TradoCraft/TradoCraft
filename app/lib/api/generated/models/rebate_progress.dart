// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_progress.g.dart';

@JsonSerializable()
class RebateProgress {
  const RebateProgress({
    required this.currency,
    required this.eligibleSales,
    required this.message,
    required this.rateYear,
    this.amountToNextTier,
    this.nextRate,
    this.nextThreshold,
  });
  
  factory RebateProgress.fromJson(Map<String, Object?> json) => _$RebateProgressFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'amount_to_next_tier')
  final String? amountToNextTier;
  final String currency;
  @JsonKey(name: 'eligible_sales')
  final String eligibleSales;
  final String message;
  @JsonKey(includeIfNull: false,name: 'next_rate')
  final String? nextRate;
  @JsonKey(includeIfNull: false,name: 'next_threshold')
  final String? nextThreshold;

  /// Calendar year for which purchases are earning a rate.
  @JsonKey(name: 'rate_year')
  final int rateYear;

  Map<String, Object?> toJson() => _$RebateProgressToJson(this);
}
