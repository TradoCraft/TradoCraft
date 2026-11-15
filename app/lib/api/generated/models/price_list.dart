// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'price_list_settings.dart';
import 'price_list_zone.dart';

part 'price_list.g.dart';

@JsonSerializable()
class PriceList {
  const PriceList({
    required this.code,
    required this.id,
    required this.itemCount,
    required this.name,
    required this.settings,
    required this.validFrom,
    required this.zones,
  });
  
  factory PriceList.fromJson(Map<String, Object?> json) => _$PriceListFromJson(json);
  
  final String code;
  final String id;
  @JsonKey(name: 'item_count')
  final int itemCount;
  final String name;
  final PriceListSettings settings;
  @JsonKey(name: 'valid_from')
  final DateTime validFrom;

  /// Zones in print order. Prices are those valid on `valid_from` in each zone.
  final List<PriceListZone> zones;

  Map<String, Object?> toJson() => _$PriceListToJson(this);
}
