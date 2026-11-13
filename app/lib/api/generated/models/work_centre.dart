// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'work_centre_hours_slot.dart';

part 'work_centre.g.dart';

/// A work centre with its own opening hours.
@JsonSerializable()
class WorkCentre {
  const WorkCentre({
    required this.active,
    required this.capacity,
    required this.code,
    required this.hours,
    required this.id,
    required this.name,
    required this.notes,
    required this.openOperations,
    required this.sortOrder,
    this.costPerHour,
    this.divisionId,
    this.divisionName,
  });
  
  factory WorkCentre.fromJson(Map<String, Object?> json) => _$WorkCentreFromJson(json);
  
  final bool active;

  /// Parallel units (machines or crews) the work centre offers at once.
  final int capacity;
  final String code;

  /// Cost of one hour of work in the company currency. Only for users with the cost permission.
  @JsonKey(includeIfNull: false,name: 'cost_per_hour')
  final String? costPerHour;
  @JsonKey(includeIfNull: false,name: 'division_id')
  final String? divisionId;
  @JsonKey(includeIfNull: false,name: 'division_name')
  final String? divisionName;

  /// Own opening hours. None: the default week (Monday to Friday 08:00-12:00 and 13:00-17:00).
  final List<WorkCentreHoursSlot> hours;
  final String id;
  final String name;
  final String notes;

  /// Operations of production orders that are not finished.
  @JsonKey(name: 'open_operations')
  final int openOperations;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$WorkCentreToJson(this);
}
