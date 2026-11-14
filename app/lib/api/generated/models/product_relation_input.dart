// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_relation_input.g.dart';

@JsonSerializable()
class ProductRelationInput {
  const ProductRelationInput({
    required this.kind,
    this.aFamilyId,
    this.aProductId,
    this.active,
    this.bFamilyId,
    this.bProductId,
    this.bidirectional,
    this.note,
    this.strength,
  });
  
  factory ProductRelationInput.fromJson(Map<String, Object?> json) => _$ProductRelationInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'a_family_id')
  final String? aFamilyId;

  /// Exactly one of `a_product_id` and `a_family_id`.
  @JsonKey(includeIfNull: false,name: 'a_product_id')
  final String? aProductId;
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false,name: 'b_family_id')
  final String? bFamilyId;

  /// Exactly one of `b_product_id` and `b_family_id`.
  @JsonKey(includeIfNull: false,name: 'b_product_id')
  final String? bProductId;
  @JsonKey(includeIfNull: false)
  final bool? bidirectional;

  /// compatible | incompatible | suggested
  final String kind;
  @JsonKey(includeIfNull: false)
  final String? note;
  @JsonKey(includeIfNull: false)
  final int? strength;

  Map<String, Object?> toJson() => _$ProductRelationInputToJson(this);
}
