// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'bom_line.g.dart';

@JsonSerializable()
class BomLine {
  const BomLine({
    required this.componentCode,
    required this.componentHasBom,
    required this.componentName,
    required this.componentProductId,
    required this.componentTracking,
    required this.componentType,
    required this.componentUnit,
    required this.notes,
    required this.position,
    required this.quantity,
    required this.scrapPercent,
  });
  
  factory BomLine.fromJson(Map<String, Object?> json) => _$BomLineFromJson(json);
  
  @JsonKey(name: 'component_code')
  final String componentCode;

  /// True if the component has an active BOM itself (a subassembly).
  @JsonKey(name: 'component_has_bom')
  final bool componentHasBom;
  @JsonKey(name: 'component_name')
  final String componentName;
  @JsonKey(name: 'component_product_id')
  final String componentProductId;
  @JsonKey(name: 'component_tracking')
  final String componentTracking;
  @JsonKey(name: 'component_type')
  final String componentType;
  @JsonKey(name: 'component_unit')
  final String componentUnit;
  final String notes;
  final int position;
  final String quantity;
  @JsonKey(name: 'scrap_percent')
  final String scrapPercent;

  Map<String, Object?> toJson() => _$BomLineToJson(this);
}
