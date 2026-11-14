// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'location.g.dart';

@JsonSerializable()
class Location {
  const Location({
    required this.active,
    required this.code,
    required this.id,
    required this.name,
    required this.warehouseId,
  });
  
  factory Location.fromJson(Map<String, Object?> json) => _$LocationFromJson(json);
  
  final bool active;
  final String code;
  final String id;
  final String name;
  @JsonKey(name: 'warehouse_id')
  final String warehouseId;

  Map<String, Object?> toJson() => _$LocationToJson(this);
}
