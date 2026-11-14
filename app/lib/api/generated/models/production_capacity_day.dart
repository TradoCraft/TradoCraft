// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_capacity_day.g.dart';

/// One day of one work centre.
@JsonSerializable()
class ProductionCapacityDay {
  const ProductionCapacityDay({
    required this.availableMinutes,
    required this.date,
    required this.loadMinutes,
    required this.overloaded,
  });
  
  factory ProductionCapacityDay.fromJson(Map<String, Object?> json) => _$ProductionCapacityDayFromJson(json);
  
  /// What the work centre can work: the minutes of its hours times its capacity, 0 on a closure.
  @JsonKey(name: 'available_minutes')
  final int availableMinutes;
  final DateTime date;

  /// What the open operations put on the day.
  @JsonKey(name: 'load_minutes')
  final int loadMinutes;

  /// The load is more than is available.
  final bool overloaded;

  Map<String, Object?> toJson() => _$ProductionCapacityDayToJson(this);
}
