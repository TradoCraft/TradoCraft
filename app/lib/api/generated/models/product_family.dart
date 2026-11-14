// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_family.g.dart';

@JsonSerializable()
class ProductFamily {
  const ProductFamily({
    required this.active,
    required this.code,
    required this.id,
    required this.name,
    required this.productCount,
  });
  
  factory ProductFamily.fromJson(Map<String, Object?> json) => _$ProductFamilyFromJson(json);
  
  final bool active;
  final String code;
  final String id;
  final String name;
  @JsonKey(name: 'product_count')
  final int productCount;

  Map<String, Object?> toJson() => _$ProductFamilyToJson(this);
}
