// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'work_centre_hours_slot.dart';

part 'work_centre_hours_input.g.dart';

/// Replaces the opening hours of a work centre.
@JsonSerializable()
class WorkCentreHoursInput {
  const WorkCentreHoursInput({
    required this.slots,
  });
  
  factory WorkCentreHoursInput.fromJson(Map<String, Object?> json) => _$WorkCentreHoursInputFromJson(json);
  
  /// All blocks; none means the default week applies again.
  final List<WorkCentreHoursSlot> slots;

  Map<String, Object?> toJson() => _$WorkCentreHoursInputToJson(this);
}
