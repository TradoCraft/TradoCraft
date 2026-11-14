// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'work_centre_input.g.dart';

/// Input to create or change a work centre.
@JsonSerializable()
class WorkCentreInput {
  const WorkCentreInput({
    required this.code,
    required this.name,
    this.active,
    this.capacity,
    this.costPerHour,
    this.divisionId,
    this.notes,
    this.sortOrder,
  });
  
  factory WorkCentreInput.fromJson(Map<String, Object?> json) => _$WorkCentreInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false)
  final int? capacity;
  final String code;

  /// Ignored (the stored rate stays) for users without the cost permission.
  @JsonKey(includeIfNull: false,name: 'cost_per_hour')
  final String? costPerHour;
  @JsonKey(includeIfNull: false,name: 'division_id')
  final String? divisionId;
  final String name;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$WorkCentreInputToJson(this);
}
