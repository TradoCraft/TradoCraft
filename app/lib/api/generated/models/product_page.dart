// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'product.dart';

part 'product_page.g.dart';

@JsonSerializable()
class ProductPage {
  const ProductPage({
    required this.items,
    required this.total,
  });
  
  factory ProductPage.fromJson(Map<String, Object?> json) => _$ProductPageFromJson(json);
  
  final List<Product> items;
  final int total;

  Map<String, Object?> toJson() => _$ProductPageToJson(this);
}
