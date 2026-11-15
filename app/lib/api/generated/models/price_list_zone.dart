// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_zone.g.dart';

/// A zone a list is published for.
@JsonSerializable()
class PriceListZone {
  const PriceListZone({
    required this.languages,
    required this.priceZoneCode,
    required this.priceZoneId,
    required this.priceZoneName,
    required this.sortOrder,
  });
  
  factory PriceListZone.fromJson(Map<String, Object?> json) => _$PriceListZoneFromJson(json);
  
  /// Languages published for this zone; the first is the default.
  final List<String> languages;
  @JsonKey(name: 'price_zone_code')
  final String priceZoneCode;
  @JsonKey(name: 'price_zone_id')
  final String priceZoneId;
  @JsonKey(name: 'price_zone_name')
  final String priceZoneName;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$PriceListZoneToJson(this);
}
