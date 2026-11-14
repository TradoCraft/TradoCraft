// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_capacity_centre.dart';

part 'production_capacity.g.dart';

@JsonSerializable()
class ProductionCapacity {
  const ProductionCapacity({
    required this.centres,
    required this.from,
    required this.to,
  });
  
  factory ProductionCapacity.fromJson(Map<String, Object?> json) => _$ProductionCapacityFromJson(json);
  
  final List<ProductionCapacityCentre> centres;
  final DateTime from;
  final DateTime to;

  Map<String, Object?> toJson() => _$ProductionCapacityToJson(this);
}
