// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_historical_input.g.dart';

@JsonSerializable()
class RebateHistoricalInput {
  const RebateHistoricalInput({
    required this.cutoff,
    required this.eligibleSales,
    required this.year,
  });
  
  factory RebateHistoricalInput.fromJson(Map<String, Object?> json) => _$RebateHistoricalInputFromJson(json);
  
  /// Date through which the imported eligible sales have been verified, inclusive.
  final DateTime cutoff;
  @JsonKey(name: 'eligible_sales')
  final String eligibleSales;
  final int year;

  Map<String, Object?> toJson() => _$RebateHistoricalInputToJson(this);
}
