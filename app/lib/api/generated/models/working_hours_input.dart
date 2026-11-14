// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'hours_slot_input.dart';

part 'working_hours_input.g.dart';

@JsonSerializable()
class WorkingHoursInput {
  const WorkingHoursInput({
    required this.slots,
    this.userId,
  });
  
  factory WorkingHoursInput.fromJson(Map<String, Object?> json) => _$WorkingHoursInputFromJson(json);
  
  /// Replaces all rows of that user (or of the default). No rows: the default applies again.
  final List<HoursSlotInput> slots;

  /// The user the hours are for; empty sets the company default.
  @JsonKey(includeIfNull: false,name: 'user_id')
  final String? userId;

  Map<String, Object?> toJson() => _$WorkingHoursInputToJson(this);
}
