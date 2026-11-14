// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_zone_input.g.dart';

/// Create/update body of a price zone.
@JsonSerializable()
class PriceZoneInput {
  const PriceZoneInput({
    required this.code,
    required this.name,
    this.sortOrder,
  });
  
  factory PriceZoneInput.fromJson(Map<String, Object?> json) => _$PriceZoneInputFromJson(json);
  
  final String code;
  final String name;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$PriceZoneInputToJson(this);
}
