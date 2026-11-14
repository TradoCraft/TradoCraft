// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_to_release.g.dart';

@JsonSerializable()
class ProductionToRelease {
  const ProductionToRelease({
    required this.customerName,
    required this.orderId,
    required this.orderLineId,
    required this.orderNumber,
    required this.ordered,
    required this.planned,
    required this.priority,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.toBuild,
  });
  
  factory ProductionToRelease.fromJson(Map<String, Object?> json) => _$ProductionToReleaseFromJson(json);
  
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(name: 'order_id')
  final String orderId;
  @JsonKey(name: 'order_line_id')
  final String orderLineId;
  @JsonKey(name: 'order_number')
  final String orderNumber;

  /// Ordered, in the stock unit.
  final String ordered;

  /// What production orders already cover.
  final String planned;

  /// low | normal | expedite
  final String priority;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;

  /// Still to be released: ordered minus planned.
  @JsonKey(name: 'to_build')
  final String toBuild;

  Map<String, Object?> toJson() => _$ProductionToReleaseToJson(this);
}
