// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_uom.g.dart';

@JsonSerializable()
class ProductUom {
  const ProductUom({
    required this.factor,
    required this.uomCode,
  });
  
  factory ProductUom.fromJson(Map<String, Object?> json) => _$ProductUomFromJson(json);
  
  /// Stock units in one of this unit (a box of 12 pieces: 12).
  final String factor;
  @JsonKey(name: 'uom_code')
  final String uomCode;

  Map<String, Object?> toJson() => _$ProductUomToJson(this);
}
