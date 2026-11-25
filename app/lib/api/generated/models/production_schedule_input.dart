// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_schedule_input.g.dart';

@JsonSerializable()
class ProductionScheduleInput {
  const ProductionScheduleInput({
    this.finite,
    this.startDate,
  });
  
  factory ProductionScheduleInput.fromJson(Map<String, Object?> json) => _$ProductionScheduleInputFromJson(json);
  
  /// Place the operations around the load of the other orders (finite loading, ADR 0090).
  /// instead of ignoring it. Defaults to false.
  @JsonKey(includeIfNull: false)
  final bool? finite;

  /// The first day work can start; defaults to today.
  @JsonKey(includeIfNull: false,name: 'start_date')
  final DateTime? startDate;

  Map<String, Object?> toJson() => _$ProductionScheduleInputToJson(this);
}
