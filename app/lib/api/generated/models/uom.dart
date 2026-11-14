// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'uom.g.dart';

@JsonSerializable()
class Uom {
  const Uom({
    required this.active,
    required this.category,
    required this.code,
    required this.factor,
    required this.name,
  });
  
  factory Uom.fromJson(Map<String, Object?> json) => _$UomFromJson(json);
  
  final bool active;

  /// unit | weight | length | area | volume | time
  final String category;
  final String code;

  /// Size in the base unit of the category (kg = 1, g = 0.001).
  final String factor;
  final String name;

  Map<String, Object?> toJson() => _$UomToJson(this);
}
