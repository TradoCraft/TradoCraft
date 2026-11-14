// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'supplier_product.g.dart';

/// A supplier price list entry for a product.
@JsonSerializable()
class SupplierProduct {
  const SupplierProduct({
    required this.companyId,
    required this.createdAt,
    required this.currency,
    required this.id,
    required this.isPreferred,
    required this.leadTimeDays,
    required this.moq,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.supplierId,
    required this.supplierName,
    required this.supplierProductCode,
    required this.supplierProductName,
    required this.unitPrice,
    required this.updatedAt,
  });
  
  factory SupplierProduct.fromJson(Map<String, Object?> json) => _$SupplierProductFromJson(json);
  
  @JsonKey(name: 'company_id')
  final String companyId;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String currency;
  final String id;
  @JsonKey(name: 'is_preferred')
  final bool isPreferred;
  @JsonKey(name: 'lead_time_days')
  final int leadTimeDays;
  final String moq;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'supplier_id')
  final String supplierId;
  @JsonKey(name: 'supplier_name')
  final String supplierName;
  @JsonKey(name: 'supplier_product_code')
  final String supplierProductCode;
  @JsonKey(name: 'supplier_product_name')
  final String supplierProductName;
  @JsonKey(name: 'unit_price')
  final String unitPrice;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$SupplierProductToJson(this);
}
