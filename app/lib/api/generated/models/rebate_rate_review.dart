// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_rate_review.g.dart';

@JsonSerializable()
class RebateRateReview {
  const RebateRateReview({
    required this.customerId,
    required this.rateYear,
    this.approvedRate,
    this.eligibleSales,
    this.proposedRate,
  });
  
  factory RebateRateReview.fromJson(Map<String, Object?> json) => _$RebateRateReviewFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'approved_rate')
  final String? approvedRate;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(includeIfNull: false,name: 'eligible_sales')
  final String? eligibleSales;
  @JsonKey(includeIfNull: false,name: 'proposed_rate')
  final String? proposedRate;

  /// Calendar year in which the approved rate is used. The sales basis is the preceding year.
  @JsonKey(name: 'rate_year')
  final int rateYear;

  Map<String, Object?> toJson() => _$RebateRateReviewToJson(this);
}
