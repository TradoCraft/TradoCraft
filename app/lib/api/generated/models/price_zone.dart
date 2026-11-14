// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_zone.g.dart';

@JsonSerializable()
class PriceZone {
  const PriceZone({
    required this.code,
    required this.id,
    required this.name,
    required this.sortOrder,
  });
  
  factory PriceZone.fromJson(Map<String, Object?> json) => _$PriceZoneFromJson(json);
  
  final String code;
  final String id;
  final String name;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$PriceZoneToJson(this);
}
