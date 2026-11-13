// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_operation_update.g.dart';

/// What a planner may change on an operation that is not finished. What is left out stays.
@JsonSerializable()
class ProductionOperationUpdate {
  const ProductionOperationUpdate({
    this.plannedEnd,
    this.plannedStart,
    this.workCentreId,
  });
  
  factory ProductionOperationUpdate.fromJson(Map<String, Object?> json) => _$ProductionOperationUpdateFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'planned_end')
  final DateTime? plannedEnd;
  @JsonKey(includeIfNull: false,name: 'planned_start')
  final DateTime? plannedStart;

  /// Move the operation to another (active) work centre; its cost rate is taken again.
  @JsonKey(includeIfNull: false,name: 'work_centre_id')
  final String? workCentreId;

  Map<String, Object?> toJson() => _$ProductionOperationUpdateToJson(this);
}
