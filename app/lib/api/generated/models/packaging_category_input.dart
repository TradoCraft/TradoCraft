// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'packaging_category_input.g.dart';

@JsonSerializable()
class PackagingCategoryInput {
  const PackagingCategoryInput({
    required this.code,
    required this.name,
    this.active,
    this.description,
    this.requiresShippingQuote,
  });
  
  factory PackagingCategoryInput.fromJson(Map<String, Object?> json) => _$PackagingCategoryInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  final String code;
  @JsonKey(includeIfNull: false)
  final String? description;
  final String name;
  @JsonKey(includeIfNull: false,name: 'requires_shipping_quote')
  final bool? requiresShippingQuote;

  Map<String, Object?> toJson() => _$PackagingCategoryInputToJson(this);
}
