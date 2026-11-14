// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'set_supplier_product_input.g.dart';

/// Payload to create or replace a supplier price list entry.
@JsonSerializable()
class SetSupplierProductInput {
  const SetSupplierProductInput({
    required this.unitPrice,
    this.currency,
    this.isPreferred,
    this.leadTimeDays,
    this.moq,
    this.supplierProductCode,
    this.supplierProductName,
  });
  
  factory SetSupplierProductInput.fromJson(Map<String, Object?> json) => _$SetSupplierProductInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? currency;
  @JsonKey(includeIfNull: false,name: 'is_preferred')
  final bool? isPreferred;
  @JsonKey(includeIfNull: false,name: 'lead_time_days')
  final int? leadTimeDays;
  @JsonKey(includeIfNull: false)
  final String? moq;
  @JsonKey(includeIfNull: false,name: 'supplier_product_code')
  final String? supplierProductCode;
  @JsonKey(includeIfNull: false,name: 'supplier_product_name')
  final String? supplierProductName;
  @JsonKey(name: 'unit_price')
  final String unitPrice;

  Map<String, Object?> toJson() => _$SetSupplierProductInputToJson(this);
}
