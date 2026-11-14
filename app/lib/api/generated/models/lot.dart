// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'lot.g.dart';

@JsonSerializable()
class Lot {
  const Lot({
    required this.id,
    required this.lotNumber,
    required this.notes,
    required this.onHand,
    required this.productCode,
    required this.productId,
    this.expiryDate,
  });
  
  factory Lot.fromJson(Map<String, Object?> json) => _$LotFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'expiry_date')
  final DateTime? expiryDate;
  final String id;
  @JsonKey(name: 'lot_number')
  final String lotNumber;
  final String notes;
  @JsonKey(name: 'on_hand')
  final String onHand;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;

  Map<String, Object?> toJson() => _$LotToJson(this);
}
