// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'requirement.g.dart';

@JsonSerializable()
class Requirement {
  const Requirement({
    required this.code,
    required this.name,
    required this.productId,
    required this.productType,
    required this.quantity,
    required this.unit,
  });
  
  factory Requirement.fromJson(Map<String, Object?> json) => _$RequirementFromJson(json);
  
  final String code;
  final String name;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_type')
  final String productType;
  final String quantity;
  final String unit;

  Map<String, Object?> toJson() => _$RequirementToJson(this);
}
