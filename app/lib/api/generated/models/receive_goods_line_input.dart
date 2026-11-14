// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'receive_goods_line_input.g.dart';

/// One purchase order line being received.
@JsonSerializable()
class ReceiveGoodsLineInput {
  const ReceiveGoodsLineInput({
    required this.poLineId,
    required this.quantity,
    this.lotNumber,
    this.serialNumbers,
  });
  
  factory ReceiveGoodsLineInput.fromJson(Map<String, Object?> json) => _$ReceiveGoodsLineInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  @JsonKey(name: 'po_line_id')
  final String poLineId;
  final String quantity;
  @JsonKey(includeIfNull: false,name: 'serial_numbers')
  final List<String>? serialNumbers;

  Map<String, Object?> toJson() => _$ReceiveGoodsLineInputToJson(this);
}
