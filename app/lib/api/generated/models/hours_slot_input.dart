// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'hours_slot_input.g.dart';

@JsonSerializable()
class HoursSlotInput {
  const HoursSlotInput({
    required this.endTime,
    required this.startTime,
    required this.weekday,
  });
  
  factory HoursSlotInput.fromJson(Map<String, Object?> json) => _$HoursSlotInputFromJson(json);
  
  @JsonKey(name: 'end_time')
  final String endTime;
  @JsonKey(name: 'start_time')
  final String startTime;
  final int weekday;

  Map<String, Object?> toJson() => _$HoursSlotInputToJson(this);
}
