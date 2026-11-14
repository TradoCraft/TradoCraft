// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_component_actual.g.dart';

@JsonSerializable()
class ProductionComponentActual {
  const ProductionComponentActual({
    required this.componentId,
    this.consumedQuantity,
    this.extraLocationId,
    this.extraLotId,
    this.scrapQuantity,
    this.serialUnitIds,
  });
  
  factory ProductionComponentActual.fromJson(Map<String, Object?> json) => _$ProductionComponentActualFromJson(json);
  
  @JsonKey(name: 'component_id')
  final String componentId;

  /// What was really consumed; defaults to what the BOM required.
  @JsonKey(includeIfNull: false,name: 'consumed_quantity')
  final String? consumedQuantity;

  /// Where stock beyond the reservation is taken from (needed when more was used than reserved).
  @JsonKey(includeIfNull: false,name: 'extra_location_id')
  final String? extraLocationId;
  @JsonKey(includeIfNull: false,name: 'extra_lot_id')
  final String? extraLotId;

  /// Lost on top of the consumption (not for serial-tracked components).
  @JsonKey(includeIfNull: false,name: 'scrap_quantity')
  final String? scrapQuantity;

  /// The serial units that were built in (needed for serial-tracked components, one per unit).
  @JsonKey(includeIfNull: false,name: 'serial_unit_ids')
  final List<String>? serialUnitIds;

  Map<String, Object?> toJson() => _$ProductionComponentActualToJson(this);
}
