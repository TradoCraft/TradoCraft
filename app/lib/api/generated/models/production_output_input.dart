// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_output_input.g.dart';

@JsonSerializable()
class ProductionOutputInput {
  const ProductionOutputInput({
    required this.locationId,
    required this.quantity,
    this.expiryDate,
    this.lotNumber,
    this.serialNumbers,
  });
  
  factory ProductionOutputInput.fromJson(Map<String, Object?> json) => _$ProductionOutputInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'expiry_date')
  final DateTime? expiryDate;

  /// The stock location the output goes to.
  @JsonKey(name: 'location_id')
  final String locationId;

  /// Needed for lot-tracked products.
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;

  /// What was built, in the stock unit. May be less than ordered; the order is then closed with.
  /// the shortfall and another production order covers the rest.
  final String quantity;

  /// Needed for serial-tracked products: one serial number per unit built.
  @JsonKey(includeIfNull: false,name: 'serial_numbers')
  final List<String>? serialNumbers;

  Map<String, Object?> toJson() => _$ProductionOutputInputToJson(this);
}
