// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'packaging_category.g.dart';

@JsonSerializable()
class PackagingCategory {
  const PackagingCategory({
    required this.active,
    required this.code,
    required this.description,
    required this.id,
    required this.name,
    required this.productCount,
    required this.requiresShippingQuote,
  });
  
  factory PackagingCategory.fromJson(Map<String, Object?> json) => _$PackagingCategoryFromJson(json);
  
  final bool active;
  final String code;
  final String description;
  final String id;
  final String name;
  @JsonKey(name: 'product_count')
  final int productCount;

  /// Quotations with products in this category wait for a shipping quote from a person.
  @JsonKey(name: 'requires_shipping_quote')
  final bool requiresShippingQuote;

  Map<String, Object?> toJson() => _$PackagingCategoryToJson(this);
}
