// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_option.g.dart';

/// An option of a product, with the option product's code and name.
@JsonSerializable()
class ProductOption {
  const ProductOption({
    required this.active,
    required this.defaultQuantity,
    required this.optionActive,
    required this.optionCode,
    required this.optionName,
    required this.optionProductId,
    required this.requiredValue,
    required this.sortOrder,
  });
  
  factory ProductOption.fromJson(Map<String, Object?> json) => _$ProductOptionFromJson(json);
  
  final bool active;

  /// Quantity of the option per unit of the parent.
  @JsonKey(name: 'default_quantity')
  final String defaultQuantity;

  /// Whether the option product itself is active; inactive ones cannot be added to quotations.
  @JsonKey(name: 'option_active')
  final bool optionActive;
  @JsonKey(name: 'option_code')
  final String optionCode;
  @JsonKey(name: 'option_name')
  final String optionName;
  @JsonKey(name: 'option_product_id')
  final String optionProductId;

  /// Added to a quotation automatically together with the parent.
  /// The name has been replaced because it contains a keyword. Original name: `required`.
  @JsonKey(name: 'required')
  final bool requiredValue;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$ProductOptionToJson(this);
}
