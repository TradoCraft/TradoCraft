// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_family_input.g.dart';

@JsonSerializable()
class ProductFamilyInput {
  const ProductFamilyInput({
    required this.code,
    required this.name,
    this.active,
  });
  
  factory ProductFamilyInput.fromJson(Map<String, Object?> json) => _$ProductFamilyInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  final String code;
  final String name;

  Map<String, Object?> toJson() => _$ProductFamilyInputToJson(this);
}
