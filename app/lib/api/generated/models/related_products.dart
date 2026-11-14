// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'product_relation.dart';
import 'suggestion.dart';

part 'related_products.g.dart';

/// What the rules and the order history say about one product.
@JsonSerializable()
class RelatedProducts {
  const RelatedProducts({
    required this.rules,
    required this.suggestions,
  });
  
  factory RelatedProducts.fromJson(Map<String, Object?> json) => _$RelatedProductsFromJson(json);
  
  /// Active rules that apply to the product, directly or through its family.
  final List<ProductRelation> rules;

  /// Manual suggestions first, then computed ones.
  final List<Suggestion> suggestions;

  Map<String, Object?> toJson() => _$RelatedProductsToJson(this);
}
