// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'incoming_line.dart';

part 'incoming_supply.g.dart';

/// Incoming supply of one product.
@JsonSerializable()
class IncomingSupply {
  const IncomingSupply({
    required this.lines,
    required this.openQuantity,
    required this.productId,
    this.nextExpectedDate,
  });
  
  factory IncomingSupply.fromJson(Map<String, Object?> json) => _$IncomingSupplyFromJson(json);
  
  final List<IncomingLine> lines;

  /// The earliest expected date among the lines that carry one.
  @JsonKey(includeIfNull: false,name: 'next_expected_date')
  final DateTime? nextExpectedDate;
  @JsonKey(name: 'open_quantity')
  final String openQuantity;
  @JsonKey(name: 'product_id')
  final String productId;

  Map<String, Object?> toJson() => _$IncomingSupplyToJson(this);
}
