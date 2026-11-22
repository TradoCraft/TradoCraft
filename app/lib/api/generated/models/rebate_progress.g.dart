// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateProgress _$RebateProgressFromJson(Map<String, dynamic> json) =>
    RebateProgress(
      currency: json['currency'] as String,
      eligibleSales: json['eligible_sales'] as String,
      message: json['message'] as String,
      rateYear: (json['rate_year'] as num).toInt(),
      amountToNextTier: json['amount_to_next_tier'] as String?,
      nextRate: json['next_rate'] as String?,
      nextThreshold: json['next_threshold'] as String?,
    );

Map<String, dynamic> _$RebateProgressToJson(RebateProgress instance) =>
    <String, dynamic>{
      'amount_to_next_tier': ?instance.amountToNextTier,
      'currency': instance.currency,
      'eligible_sales': instance.eligibleSales,
      'message': instance.message,
      'next_rate': ?instance.nextRate,
      'next_threshold': ?instance.nextThreshold,
      'rate_year': instance.rateYear,
    };
