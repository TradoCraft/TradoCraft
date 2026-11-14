// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'holiday_input.g.dart';

@JsonSerializable()
class HolidayInput {
  const HolidayInput({
    required this.day,
    required this.name,
  });
  
  factory HolidayInput.fromJson(Map<String, Object?> json) => _$HolidayInputFromJson(json);
  
  final DateTime day;
  final String name;

  Map<String, Object?> toJson() => _$HolidayInputToJson(this);
}
