// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'time_entry_input.g.dart';

@JsonSerializable()
class TimeEntryInput {
  const TimeEntryInput({
    required this.minutes,
    this.billable,
    this.note,
  });
  
  factory TimeEntryInput.fromJson(Map<String, Object?> json) => _$TimeEntryInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? billable;

  /// 1 to 1440.
  final int minutes;
  @JsonKey(includeIfNull: false)
  final String? note;

  Map<String, Object?> toJson() => _$TimeEntryInputToJson(this);
}
