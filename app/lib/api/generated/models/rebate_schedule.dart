// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'rebate_tier.dart';

part 'rebate_schedule.g.dart';

@JsonSerializable()
class RebateSchedule {
  const RebateSchedule({
    required this.effectiveYear,
    required this.id,
    required this.name,
    required this.tiers,
  });
  
  factory RebateSchedule.fromJson(Map<String, Object?> json) => _$RebateScheduleFromJson(json);
  
  @JsonKey(name: 'effective_year')
  final int effectiveYear;
  final String id;
  final String name;
  final List<RebateTier> tiers;

  Map<String, Object?> toJson() => _$RebateScheduleToJson(this);
}
