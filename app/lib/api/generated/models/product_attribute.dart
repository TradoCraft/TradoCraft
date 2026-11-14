// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'attribute_kind.dart';

part 'product_attribute.g.dart';

/// One attribute. `value` is text in JSON: a decimal for `number` (e.g. `"0.55"`), `true` or.
/// `false` for `boolean`. A `range` uses `value_min` and `value_max` (decimals) instead; its.
/// `value` is ignored on input and shown as `min..max` on output.
@JsonSerializable()
class ProductAttribute {
  const ProductAttribute({
    required this.key,
    required this.kind,
    required this.value,
    this.unit,
    this.valueMax,
    this.valueMin,
  });
  
  factory ProductAttribute.fromJson(Map<String, Object?> json) => _$ProductAttributeFromJson(json);
  
  /// Letters, digits and `_`, not starting with a digit, e.g. `kw`.
  final String key;
  final AttributeKind kind;

  /// Display unit, e.g. `kW`.
  @JsonKey(includeIfNull: false)
  final String? unit;
  final String value;

  /// Upper bound of a `range`; must be absent for the other kinds.
  @JsonKey(includeIfNull: false,name: 'value_max')
  final String? valueMax;

  /// Lower bound of a `range`; must be absent for the other kinds.
  @JsonKey(includeIfNull: false,name: 'value_min')
  final String? valueMin;

  Map<String, Object?> toJson() => _$ProductAttributeToJson(this);
}
