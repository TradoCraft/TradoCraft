// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_division.g.dart';

/// The division that normally builds a product.
@JsonSerializable()
class ProductDivision {
  const ProductDivision({
    this.divisionId,
  });
  
  factory ProductDivision.fromJson(Map<String, Object?> json) => _$ProductDivisionFromJson(json);
  
  /// The division that normally builds the product; empty when none is set.
  @JsonKey(includeIfNull: false,name: 'division_id')
  final String? divisionId;

  Map<String, Object?> toJson() => _$ProductDivisionToJson(this);
}
