// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'routing_operation.g.dart';

/// One operation of a routing.
@JsonSerializable()
class RoutingOperation {
  const RoutingOperation({
    required this.id,
    required this.name,
    required this.notes,
    required this.position,
    required this.runMinutesPerUnit,
    required this.setupMinutes,
    required this.workCentreCode,
    required this.workCentreId,
    required this.workCentreName,
  });
  
  factory RoutingOperation.fromJson(Map<String, Object?> json) => _$RoutingOperationFromJson(json);
  
  final String id;
  final String name;
  final String notes;
  final int position;

  /// Minutes for each unit built, in the stock unit of the product.
  @JsonKey(name: 'run_minutes_per_unit')
  final String runMinutesPerUnit;

  /// Minutes once per production order, whatever its quantity.
  @JsonKey(name: 'setup_minutes')
  final int setupMinutes;
  @JsonKey(name: 'work_centre_code')
  final String workCentreCode;
  @JsonKey(name: 'work_centre_id')
  final String workCentreId;
  @JsonKey(name: 'work_centre_name')
  final String workCentreName;

  Map<String, Object?> toJson() => _$RoutingOperationToJson(this);
}
