// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'new_po_line_input.g.dart';

/// A line of a new purchase order.
@JsonSerializable()
class NewPoLineInput {
  const NewPoLineInput({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.description,
    this.supplierProductCode,
  });
  
  factory NewPoLineInput.fromJson(Map<String, Object?> json) => _$NewPoLineInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? description;
  @JsonKey(name: 'product_id')
  final String productId;
  final String quantity;
  @JsonKey(includeIfNull: false,name: 'supplier_product_code')
  final String? supplierProductCode;
  @JsonKey(name: 'unit_price')
  final String unitPrice;

  Map<String, Object?> toJson() => _$NewPoLineInputToJson(this);
}
