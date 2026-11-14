// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'product_uom.dart';

part 'product_uoms_input.g.dart';

@JsonSerializable()
class ProductUomsInput {
  const ProductUomsInput({
    required this.uoms,
  });
  
  factory ProductUomsInput.fromJson(Map<String, Object?> json) => _$ProductUomsInputFromJson(json);
  
  final List<ProductUom> uoms;

  Map<String, Object?> toJson() => _$ProductUomsInputToJson(this);
}
