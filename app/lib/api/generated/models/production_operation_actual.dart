// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_operation_actual.g.dart';

/// The minutes worked on one operation, given when the order is completed.
@JsonSerializable()
class ProductionOperationActual {
  const ProductionOperationActual({
    required this.operationId,
    this.actualMinutes,
  });
  
  factory ProductionOperationActual.fromJson(Map<String, Object?> json) => _$ProductionOperationActualFromJson(json);
  
  /// Total minutes worked; defaults to the planned minutes.
  @JsonKey(includeIfNull: false,name: 'actual_minutes')
  final int? actualMinutes;
  @JsonKey(name: 'operation_id')
  final String operationId;

  Map<String, Object?> toJson() => _$ProductionOperationActualToJson(this);
}
