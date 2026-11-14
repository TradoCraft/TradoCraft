// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'product_match.dart';
import 'status_counts.dart';

part 'product_match_page.g.dart';

@JsonSerializable()
class ProductMatchPage {
  const ProductMatchPage({
    required this.counts,
    required this.items,
    required this.total,
  });
  
  factory ProductMatchPage.fromJson(Map<String, Object?> json) => _$ProductMatchPageFromJson(json);
  
  /// Products per status within the family filter, ignoring the status filter.
  final StatusCounts counts;

  /// The requested page of the products with the asked status, in product code order.
  final List<ProductMatch> items;

  /// Number of products with the asked status (all statuses without a filter).
  final int total;

  Map<String, Object?> toJson() => _$ProductMatchPageToJson(this);
}
