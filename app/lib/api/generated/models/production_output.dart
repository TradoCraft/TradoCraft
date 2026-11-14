// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_output.g.dart';

@JsonSerializable()
class ProductionOutput {
  const ProductionOutput({
    required this.id,
    required this.quantity,
    required this.stockMoveId,
    this.lotNumber,
    this.serialNumber,
  });
  
  factory ProductionOutput.fromJson(Map<String, Object?> json) => _$ProductionOutputFromJson(json);
  
  final String id;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  final String quantity;
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;
  @JsonKey(name: 'stock_move_id')
  final String stockMoveId;

  Map<String, Object?> toJson() => _$ProductionOutputToJson(this);
}
