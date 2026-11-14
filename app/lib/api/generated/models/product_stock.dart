// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_stock.g.dart';

/// Stock of one product over all locations.
@JsonSerializable()
class ProductStock {
  const ProductStock({
    required this.available,
    required this.belowReorder,
    required this.code,
    required this.inVans,
    required this.name,
    required this.onHand,
    required this.productId,
    required this.reserved,
    required this.tracking,
    required this.unit,
    this.barcode,
    this.leadTimeDays,
    this.reorderMax,
    this.reorderMin,
  });
  
  factory ProductStock.fromJson(Map<String, Object?> json) => _$ProductStockFromJson(json);
  
  final String available;
  @JsonKey(includeIfNull: false)
  final String? barcode;

  /// Available is below the reorder minimum.
  @JsonKey(name: 'below_reorder')
  final bool belowReorder;
  final String code;

  /// In service vans; not part of the other numbers unless a van is chosen.
  @JsonKey(name: 'in_vans')
  final String inVans;
  @JsonKey(includeIfNull: false,name: 'lead_time_days')
  final int? leadTimeDays;
  final String name;

  /// In the warehouses (or in the chosen warehouse).
  @JsonKey(name: 'on_hand')
  final String onHand;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(includeIfNull: false,name: 'reorder_max')
  final String? reorderMax;
  @JsonKey(includeIfNull: false,name: 'reorder_min')
  final String? reorderMin;
  final String reserved;
  final String tracking;
  final String unit;

  Map<String, Object?> toJson() => _$ProductStockToJson(this);
}
