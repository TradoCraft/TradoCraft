// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'product_stock.dart';

part 'product_stock_page.g.dart';

@JsonSerializable()
class ProductStockPage {
  const ProductStockPage({
    required this.items,
    required this.total,
  });
  
  factory ProductStockPage.fromJson(Map<String, Object?> json) => _$ProductStockPageFromJson(json);
  
  final List<ProductStock> items;
  final int total;

  Map<String, Object?> toJson() => _$ProductStockPageToJson(this);
}
