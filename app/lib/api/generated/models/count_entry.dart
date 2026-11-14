// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'count_entry.g.dart';

@JsonSerializable()
class CountEntry {
  const CountEntry({
    this.countedQuantity,
    this.expiryDate,
    this.lineId,
    this.locationId,
    this.lotId,
    this.lotNumber,
    this.productId,
  });
  
  factory CountEntry.fromJson(Map<String, Object?> json) => _$CountEntryFromJson(json);
  
  /// The counted quantity; null clears it (the line is left alone when posting).
  @JsonKey(includeIfNull: false,name: 'counted_quantity')
  final String? countedQuantity;
  @JsonKey(includeIfNull: false,name: 'expiry_date')
  final DateTime? expiryDate;

  /// An existing line...
  @JsonKey(includeIfNull: false,name: 'line_id')
  final String? lineId;
  @JsonKey(includeIfNull: false,name: 'location_id')
  final String? locationId;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;

  /// ...or stock that was not expected: product, location and lot.
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  Map<String, Object?> toJson() => _$CountEntryToJson(this);
}
