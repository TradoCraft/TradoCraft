// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_relation.g.dart';

@JsonSerializable()
class ProductRelation {
  const ProductRelation({
    required this.active,
    required this.bidirectional,
    required this.id,
    required this.kind,
    required this.note,
    required this.strength,
    this.aFamilyCode,
    this.aFamilyId,
    this.aProductCode,
    this.aProductId,
    this.bFamilyCode,
    this.bFamilyId,
    this.bProductCode,
    this.bProductId,
  });
  
  factory ProductRelation.fromJson(Map<String, Object?> json) => _$ProductRelationFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'a_family_code')
  final String? aFamilyCode;
  @JsonKey(includeIfNull: false,name: 'a_family_id')
  final String? aFamilyId;
  @JsonKey(includeIfNull: false,name: 'a_product_code')
  final String? aProductCode;
  @JsonKey(includeIfNull: false,name: 'a_product_id')
  final String? aProductId;
  final bool active;
  @JsonKey(includeIfNull: false,name: 'b_family_code')
  final String? bFamilyCode;
  @JsonKey(includeIfNull: false,name: 'b_family_id')
  final String? bFamilyId;
  @JsonKey(includeIfNull: false,name: 'b_product_code')
  final String? bProductCode;
  @JsonKey(includeIfNull: false,name: 'b_product_id')
  final String? bProductId;

  /// The rule also applies with the sides swapped.
  final bool bidirectional;
  final String id;

  /// compatible | incompatible | suggested
  final String kind;
  final String note;

  /// 1 to 100, the weight of a suggested rule.
  final int strength;

  Map<String, Object?> toJson() => _$ProductRelationToJson(this);
}
