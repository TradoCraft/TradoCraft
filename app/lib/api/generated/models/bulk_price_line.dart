// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'bulk_price_line.g.dart';

@JsonSerializable()
class BulkPriceLine {
  const BulkPriceLine({
    required this.conflict,
    required this.currentPrice,
    required this.currentValidFrom,
    required this.newPrice,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.zoneCode,
    required this.zoneId,
  });
  
  factory BulkPriceLine.fromJson(Map<String, Object?> json) => _$BulkPriceLineFromJson(json);
  
  /// A price starting on exactly `valid_from` already exists.
  final bool conflict;

  /// Price valid on `valid_from` before the change.
  @JsonKey(name: 'current_price')
  final String currentPrice;
  @JsonKey(name: 'current_valid_from')
  final DateTime currentValidFrom;
  @JsonKey(name: 'new_price')
  final String newPrice;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'zone_code')
  final String zoneCode;
  @JsonKey(name: 'zone_id')
  final String zoneId;

  Map<String, Object?> toJson() => _$BulkPriceLineToJson(this);
}
