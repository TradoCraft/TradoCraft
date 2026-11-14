// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_option_input.g.dart';

/// One option as set from the product screen.
@JsonSerializable()
class ProductOptionInput {
  const ProductOptionInput({
    required this.optionProductId,
    this.active,
    this.defaultQuantity,
    this.requiredValue,
    this.sortOrder,
  });
  
  factory ProductOptionInput.fromJson(Map<String, Object?> json) => _$ProductOptionInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false,name: 'default_quantity')
  final String? defaultQuantity;
  @JsonKey(name: 'option_product_id')
  final String optionProductId;

  /// The name has been replaced because it contains a keyword. Original name: `required`.
  @JsonKey(includeIfNull: false,name: 'required')
  final bool? requiredValue;

  /// Defaults to the position in the list.
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$ProductOptionInputToJson(this);
}
