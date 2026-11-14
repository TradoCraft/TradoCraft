// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'holiday.g.dart';

@JsonSerializable()
class Holiday {
  const Holiday({
    required this.day,
    required this.id,
    required this.name,
  });
  
  factory Holiday.fromJson(Map<String, Object?> json) => _$HolidayFromJson(json);
  
  final DateTime day;
  final String id;
  final String name;

  Map<String, Object?> toJson() => _$HolidayToJson(this);
}
