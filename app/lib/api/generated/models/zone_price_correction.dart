// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'zone_price_correction.g.dart';

/// A correction of a zone price that has not started yet.
@JsonSerializable()
class ZonePriceCorrection {
  const ZonePriceCorrection({
    required this.unitPrice,
    required this.validFrom,
  });
  
  factory ZonePriceCorrection.fromJson(Map<String, Object?> json) => _$ZonePriceCorrectionFromJson(json);
  
  @JsonKey(name: 'unit_price')
  final String unitPrice;

  /// The (possibly corrected) first day of the price; after today.
  @JsonKey(name: 'valid_from')
  final DateTime validFrom;

  Map<String, Object?> toJson() => _$ZonePriceCorrectionToJson(this);
}
