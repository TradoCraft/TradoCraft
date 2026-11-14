// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'count_input.g.dart';

@JsonSerializable()
class CountInput {
  const CountInput({
    required this.warehouseId,
    this.locationId,
    this.note,
    this.productId,
  });
  
  factory CountInput.fromJson(Map<String, Object?> json) => _$CountInputFromJson(json);
  
  /// Count only this location.
  @JsonKey(includeIfNull: false,name: 'location_id')
  final String? locationId;
  @JsonKey(includeIfNull: false)
  final String? note;

  /// Count only this product.
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  @JsonKey(name: 'warehouse_id')
  final String warehouseId;

  Map<String, Object?> toJson() => _$CountInputToJson(this);
}
