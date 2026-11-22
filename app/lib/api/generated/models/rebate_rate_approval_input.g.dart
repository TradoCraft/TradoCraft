// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_rate_approval_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateRateApprovalInput _$RebateRateApprovalInputFromJson(
  Map<String, dynamic> json,
) => RebateRateApprovalInput(
  rateYear: (json['rate_year'] as num).toInt(),
  eligibleSales: json['eligible_sales'] as String?,
  proposedRate: json['proposed_rate'] as String?,
);

Map<String, dynamic> _$RebateRateApprovalInputToJson(
  RebateRateApprovalInput instance,
) => <String, dynamic>{
  'eligible_sales': ?instance.eligibleSales,
  'proposed_rate': ?instance.proposedRate,
  'rate_year': instance.rateYear,
};
