// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'update_production_input.g.dart';

@JsonSerializable()
class UpdateProductionInput {
  const UpdateProductionInput({
    this.divisionId,
    this.notes,
    this.plannedReadyDate,
  });
  
  factory UpdateProductionInput.fromJson(Map<String, Object?> json) => _$UpdateProductionInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'division_id')
  final String? divisionId;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'planned_ready_date')
  final DateTime? plannedReadyDate;

  Map<String, Object?> toJson() => _$UpdateProductionInputToJson(this);
}
