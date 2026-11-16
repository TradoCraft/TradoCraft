// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'new_po_line_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NewPoLineInput _$NewPoLineInputFromJson(Map<String, dynamic> json) =>
    NewPoLineInput(
      productId: json['product_id'] as String,
      quantity: json['quantity'] as String,
      unitPrice: json['unit_price'] as String,
      description: json['description'] as String?,
      supplierProductCode: json['supplier_product_code'] as String?,
      vatRate: json['vat_rate'] as String?,
    );

Map<String, dynamic> _$NewPoLineInputToJson(NewPoLineInput instance) =>
    <String, dynamic>{
      'description': ?instance.description,
      'product_id': instance.productId,
      'quantity': instance.quantity,
      'supplier_product_code': ?instance.supplierProductCode,
      'unit_price': instance.unitPrice,
      'vat_rate': ?instance.vatRate,
    };
