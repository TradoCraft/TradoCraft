// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'new_po_line_input.dart';

part 'new_purchase_order_input.g.dart';

/// Payload to create a draft purchase order.
@JsonSerializable()
class NewPurchaseOrderInput {
  const NewPurchaseOrderInput({
    required this.lines,
    required this.supplierId,
    this.currency,
    this.expectedDeliveryDate,
    this.notes,
    this.orderDate,
  });
  
  factory NewPurchaseOrderInput.fromJson(Map<String, Object?> json) => _$NewPurchaseOrderInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? currency;
  @JsonKey(includeIfNull: false,name: 'expected_delivery_date')
  final DateTime? expectedDeliveryDate;
  final List<NewPoLineInput> lines;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'order_date')
  final DateTime? orderDate;
  @JsonKey(name: 'supplier_id')
  final String supplierId;

  Map<String, Object?> toJson() => _$NewPurchaseOrderInputToJson(this);
}
