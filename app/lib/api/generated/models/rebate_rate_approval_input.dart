// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_rate_approval_input.g.dart';

@JsonSerializable()
class RebateRateApprovalInput {
  const RebateRateApprovalInput({
    required this.rateYear,
  });
  
  factory RebateRateApprovalInput.fromJson(Map<String, Object?> json) => _$RebateRateApprovalInputFromJson(json);
  
  @JsonKey(name: 'rate_year')
  final int rateYear;

  Map<String, Object?> toJson() => _$RebateRateApprovalInputToJson(this);
}
