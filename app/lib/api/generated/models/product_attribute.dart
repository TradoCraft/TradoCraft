// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'attribute_kind.dart';

part 'product_attribute.g.dart';

/// One attribute. `value` is text in JSON: a decimal for `number` (e.g. `"0.55"`), `true` or.
/// `false` for `boolean`.
@JsonSerializable()
class ProductAttribute {
  const ProductAttribute({
    required this.key,
    required this.kind,
    required this.value,
    this.unit,
  });
  
  factory ProductAttribute.fromJson(Map<String, Object?> json) => _$ProductAttributeFromJson(json);
  
  /// Letters, digits and `_`, not starting with a digit, e.g. `kw`.
  final String key;
  final AttributeKind kind;

  /// Display unit, e.g. `kW`.
  @JsonKey(includeIfNull: false)
  final String? unit;
  final String value;

  Map<String, Object?> toJson() => _$ProductAttributeToJson(this);
}
