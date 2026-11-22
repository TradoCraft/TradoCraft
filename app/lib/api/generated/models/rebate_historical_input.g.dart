// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_historical_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateHistoricalInput _$RebateHistoricalInputFromJson(
  Map<String, dynamic> json,
) => RebateHistoricalInput(
  cutoff: DateTime.parse(json['cutoff'] as String),
  eligibleSales: json['eligible_sales'] as String,
  year: (json['year'] as num).toInt(),
);

Map<String, dynamic> _$RebateHistoricalInputToJson(
  RebateHistoricalInput instance,
) => <String, dynamic>{
  'cutoff': instance.cutoff.toIso8601String(),
  'eligible_sales': instance.eligibleSales,
  'year': instance.year,
};
