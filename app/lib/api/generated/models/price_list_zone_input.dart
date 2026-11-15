// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_zone_input.g.dart';

/// One zone of a list; the position in the request is the print order.
@JsonSerializable()
class PriceListZoneInput {
  const PriceListZoneInput({
    required this.languages,
    required this.priceZoneId,
  });
  
  factory PriceListZoneInput.fromJson(Map<String, Object?> json) => _$PriceListZoneInputFromJson(json);
  
  /// Subset of nl, fr, en, de, es; the first is the default.
  final List<String> languages;
  @JsonKey(name: 'price_zone_id')
  final String priceZoneId;

  Map<String, Object?> toJson() => _$PriceListZoneInputToJson(this);
}
