// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'zone_price_input.g.dart';

@JsonSerializable()
class ZonePriceInput {
  const ZonePriceInput({
    required this.unitPrice,
    required this.validFrom,
    required this.zoneId,
  });
  
  factory ZonePriceInput.fromJson(Map<String, Object?> json) => _$ZonePriceInputFromJson(json);
  
  @JsonKey(name: 'unit_price')
  final String unitPrice;
  @JsonKey(name: 'valid_from')
  final DateTime validFrom;
  @JsonKey(name: 'zone_id')
  final String zoneId;

  Map<String, Object?> toJson() => _$ZonePriceInputToJson(this);
}
