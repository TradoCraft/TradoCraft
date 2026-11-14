// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_capacity_day.dart';

part 'production_capacity_centre.g.dart';

/// A work centre over the period.
@JsonSerializable()
class ProductionCapacityCentre {
  const ProductionCapacityCentre({
    required this.active,
    required this.capacity,
    required this.code,
    required this.days,
    required this.id,
    required this.name,
    required this.totalAvailableMinutes,
    required this.totalLoadMinutes,
    this.divisionId,
  });
  
  factory ProductionCapacityCentre.fromJson(Map<String, Object?> json) => _$ProductionCapacityCentreFromJson(json);
  
  final bool active;
  final int capacity;
  final String code;
  final List<ProductionCapacityDay> days;
  @JsonKey(includeIfNull: false,name: 'division_id')
  final String? divisionId;
  final String id;
  final String name;
  @JsonKey(name: 'total_available_minutes')
  final int totalAvailableMinutes;
  @JsonKey(name: 'total_load_minutes')
  final int totalLoadMinutes;

  Map<String, Object?> toJson() => _$ProductionCapacityCentreToJson(this);
}
