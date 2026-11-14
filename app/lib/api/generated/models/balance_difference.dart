// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'balance_difference.g.dart';

@JsonSerializable()
class BalanceDifference {
  const BalanceDifference({
    required this.balanceQuantity,
    required this.ledgerQuantity,
    required this.locationId,
    required this.productId,
    this.lotId,
  });
  
  factory BalanceDifference.fromJson(Map<String, Object?> json) => _$BalanceDifferenceFromJson(json);
  
  /// What the balance table holds.
  @JsonKey(name: 'balance_quantity')
  final String balanceQuantity;

  /// Sum of the moves.
  @JsonKey(name: 'ledger_quantity')
  final String ledgerQuantity;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(name: 'product_id')
  final String productId;

  Map<String, Object?> toJson() => _$BalanceDifferenceToJson(this);
}
