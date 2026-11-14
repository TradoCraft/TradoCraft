// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'portal_order_line.g.dart';

@JsonSerializable()
class PortalOrderLine {
  const PortalOrderLine({
    required this.description,
    required this.lineTotal,
    required this.listUnitPrice,
    required this.netUnitPrice,
    required this.position,
    required this.productCode,
    required this.quantity,
    required this.unit,
    required this.vatRate,
  });
  
  factory PortalOrderLine.fromJson(Map<String, Object?> json) => _$PortalOrderLineFromJson(json);
  
  final String description;
  @JsonKey(name: 'line_total')
  final String lineTotal;
  @JsonKey(name: 'list_unit_price')
  final String listUnitPrice;
  @JsonKey(name: 'net_unit_price')
  final String netUnitPrice;
  final int position;
  @JsonKey(name: 'product_code')
  final String productCode;
  final String quantity;
  final String unit;
  @JsonKey(name: 'vat_rate')
  final String vatRate;

  Map<String, Object?> toJson() => _$PortalOrderLineToJson(this);
}
