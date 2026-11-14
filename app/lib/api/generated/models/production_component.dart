// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_component.g.dart';

@JsonSerializable()
class ProductionComponent {
  const ProductionComponent({
    required this.componentCode,
    required this.componentName,
    required this.componentProductId,
    required this.consumedQuantity,
    required this.id,
    required this.manufactured,
    required this.position,
    required this.requiredQuantity,
    required this.reservedQuantity,
    required this.scrapQuantity,
    required this.short,
    required this.tracking,
    required this.unit,
  });
  
  factory ProductionComponent.fromJson(Map<String, Object?> json) => _$ProductionComponentFromJson(json);
  
  @JsonKey(name: 'component_code')
  final String componentCode;
  @JsonKey(name: 'component_name')
  final String componentName;
  @JsonKey(name: 'component_product_id')
  final String componentProductId;
  @JsonKey(name: 'consumed_quantity')
  final String consumedQuantity;
  final String id;

  /// The component is itself built from a BOM: it may need a production order of its own.
  final bool manufactured;
  final int position;
  @JsonKey(name: 'required_quantity')
  final String requiredQuantity;

  /// What is reserved for it in stock right now.
  @JsonKey(name: 'reserved_quantity')
  final String reservedQuantity;
  @JsonKey(name: 'scrap_quantity')
  final String scrapQuantity;

  /// Not (fully) reserved while the order is still open: stock is short.
  final bool short;

  /// none | serial | lot
  final String tracking;
  final String unit;

  Map<String, Object?> toJson() => _$ProductionComponentToJson(this);
}
