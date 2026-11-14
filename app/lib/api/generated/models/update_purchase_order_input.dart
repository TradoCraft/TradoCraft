// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'new_po_line_input.dart';

part 'update_purchase_order_input.g.dart';

/// Payload to change a draft purchase order.
@JsonSerializable()
class UpdatePurchaseOrderInput {
  const UpdatePurchaseOrderInput({
    this.currency,
    this.expectedDeliveryDate,
    this.lines,
    this.notes,
  });
  
  factory UpdatePurchaseOrderInput.fromJson(Map<String, Object?> json) => _$UpdatePurchaseOrderInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? currency;
  @JsonKey(includeIfNull: false,name: 'expected_delivery_date')
  final DateTime? expectedDeliveryDate;
  @JsonKey(includeIfNull: false)
  final List<NewPoLineInput>? lines;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$UpdatePurchaseOrderInputToJson(this);
}
