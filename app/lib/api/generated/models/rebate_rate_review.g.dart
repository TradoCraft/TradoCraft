// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_rate_review.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateRateReview _$RebateRateReviewFromJson(Map<String, dynamic> json) =>
    RebateRateReview(
      customerId: json['customer_id'] as String,
      rateYear: (json['rate_year'] as num).toInt(),
      approvedRate: json['approved_rate'] as String?,
      eligibleSales: json['eligible_sales'] as String?,
      proposedRate: json['proposed_rate'] as String?,
    );

Map<String, dynamic> _$RebateRateReviewToJson(RebateRateReview instance) =>
    <String, dynamic>{
      'approved_rate': ?instance.approvedRate,
      'customer_id': instance.customerId,
      'eligible_sales': ?instance.eligibleSales,
      'proposed_rate': ?instance.proposedRate,
      'rate_year': instance.rateYear,
    };
