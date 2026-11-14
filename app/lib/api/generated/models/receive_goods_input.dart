// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'receive_goods_line_input.dart';

part 'receive_goods_input.g.dart';

/// Payload to book a goods receipt against a purchase order.
@JsonSerializable()
class ReceiveGoodsInput {
  const ReceiveGoodsInput({
    required this.lines,
    required this.locationId,
    required this.warehouseId,
    this.carrier,
    this.notes,
    this.supplierDeliveryNote,
    this.trackingNumber,
  });
  
  factory ReceiveGoodsInput.fromJson(Map<String, Object?> json) => _$ReceiveGoodsInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? carrier;
  final List<ReceiveGoodsLineInput> lines;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'supplier_delivery_note')
  final String? supplierDeliveryNote;
  @JsonKey(includeIfNull: false,name: 'tracking_number')
  final String? trackingNumber;
  @JsonKey(name: 'warehouse_id')
  final String warehouseId;

  Map<String, Object?> toJson() => _$ReceiveGoodsInputToJson(this);
}
