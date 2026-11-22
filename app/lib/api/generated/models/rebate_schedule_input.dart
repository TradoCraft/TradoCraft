// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'rebate_tier.dart';

part 'rebate_schedule_input.g.dart';

@JsonSerializable()
class RebateScheduleInput {
  const RebateScheduleInput({
    required this.effectiveYear,
    required this.name,
    required this.tiers,
  });
  
  factory RebateScheduleInput.fromJson(Map<String, Object?> json) => _$RebateScheduleInputFromJson(json);
  
  /// First pricing year for this version of the schedule.
  @JsonKey(name: 'effective_year')
  final int effectiveYear;
  final String name;
  final List<RebateTier> tiers;

  Map<String, Object?> toJson() => _$RebateScheduleInputToJson(this);
}
