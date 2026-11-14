// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'zone_price_entry.g.dart';

@JsonSerializable()
class ZonePriceEntry {
  const ZonePriceEntry({
    required this.id,
    required this.unitPrice,
    required this.validFrom,
    required this.zoneCode,
    required this.zoneId,
  });
  
  factory ZonePriceEntry.fromJson(Map<String, Object?> json) => _$ZonePriceEntryFromJson(json);
  
  final String id;
  @JsonKey(name: 'unit_price')
  final String unitPrice;
  @JsonKey(name: 'valid_from')
  final DateTime validFrom;
  @JsonKey(name: 'zone_code')
  final String zoneCode;
  @JsonKey(name: 'zone_id')
  final String zoneId;

  Map<String, Object?> toJson() => _$ZonePriceEntryToJson(this);
}
