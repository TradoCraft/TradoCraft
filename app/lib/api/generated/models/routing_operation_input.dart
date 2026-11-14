// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'routing_operation_input.g.dart';

@JsonSerializable()
class RoutingOperationInput {
  const RoutingOperationInput({
    required this.name,
    required this.workCentreId,
    this.notes,
    this.runMinutesPerUnit,
    this.setupMinutes,
  });
  
  factory RoutingOperationInput.fromJson(Map<String, Object?> json) => _$RoutingOperationInputFromJson(json);
  
  final String name;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'run_minutes_per_unit')
  final String? runMinutesPerUnit;
  @JsonKey(includeIfNull: false,name: 'setup_minutes')
  final int? setupMinutes;
  @JsonKey(name: 'work_centre_id')
  final String workCentreId;

  Map<String, Object?> toJson() => _$RoutingOperationInputToJson(this);
}
