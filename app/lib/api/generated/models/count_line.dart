// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'count_line.g.dart';

@JsonSerializable()
class CountLine {
  const CountLine({
    required this.expectedQuantity,
    required this.id,
    required this.location,
    required this.locationId,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.unit,
    this.adjustmentMoveId,
    this.countedQuantity,
    this.differenceToExpected,
    this.lotId,
    this.lotNumber,
    this.quantityAtPost,
  });
  
  factory CountLine.fromJson(Map<String, Object?> json) => _$CountLineFromJson(json);
  
  /// The adjustment posted for this line.
  @JsonKey(includeIfNull: false,name: 'adjustment_move_id')
  final String? adjustmentMoveId;
  @JsonKey(includeIfNull: false,name: 'counted_quantity')
  final String? countedQuantity;

  /// Counted minus expected: what the count found against what the system expected when it.
  /// started. Differs from the adjustment when stock moved during the count.
  @JsonKey(includeIfNull: false,name: 'difference_to_expected')
  final String? differenceToExpected;

  /// What the system expected when the count was created.
  @JsonKey(name: 'expected_quantity')
  final String expectedQuantity;
  final String id;
  final String location;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;

  /// The stock at the moment the count was posted (the adjustment is counted minus this).
  @JsonKey(includeIfNull: false,name: 'quantity_at_post')
  final String? quantityAtPost;
  final String unit;

  Map<String, Object?> toJson() => _$CountLineToJson(this);
}
