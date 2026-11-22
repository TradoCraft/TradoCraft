// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_historical_total.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateHistoricalTotal _$RebateHistoricalTotalFromJson(
  Map<String, dynamic> json,
) => RebateHistoricalTotal(
  customerId: json['customer_id'] as String,
  cutoff: DateTime.parse(json['cutoff'] as String),
  eligibleSales: json['eligible_sales'] as String,
  year: (json['year'] as num).toInt(),
);

Map<String, dynamic> _$RebateHistoricalTotalToJson(
  RebateHistoricalTotal instance,
) => <String, dynamic>{
  'customer_id': instance.customerId,
  'cutoff': instance.cutoff.toIso8601String(),
  'eligible_sales': instance.eligibleSales,
  'year': instance.year,
};
