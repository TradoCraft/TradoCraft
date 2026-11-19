// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderLine _$OrderLineFromJson(Map<String, dynamic> json) => OrderLine(
  description: json['description'] as String,
  id: json['id'] as String,
  lineDiscountPercent: json['line_discount_percent'] as String,
  lineTotal: json['line_total'] as String,
  listUnitPrice: json['list_unit_price'] as String,
  netUnitPrice: json['net_unit_price'] as String,
  nonDiscountable: json['non_discountable'] as bool,
  position: (json['position'] as num).toInt(),
  priceIsIndicative: json['price_is_indicative'] as bool,
  priceOnRequest: json['price_on_request'] as bool,
  productCode: json['product_code'] as String,
  quantity: json['quantity'] as String,
  rebatePercent: json['rebate_percent'] as String,
  unit: json['unit'] as String,
  vatRate: json['vat_rate'] as String,
  customerRemark: json['customer_remark'] as String?,
  productId: json['product_id'] as String?,
  productionRemark: json['production_remark'] as String?,
);

Map<String, dynamic> _$OrderLineToJson(OrderLine instance) => <String, dynamic>{
  'customer_remark': ?instance.customerRemark,
  'description': instance.description,
  'id': instance.id,
  'line_discount_percent': instance.lineDiscountPercent,
  'line_total': instance.lineTotal,
  'list_unit_price': instance.listUnitPrice,
  'net_unit_price': instance.netUnitPrice,
  'non_discountable': instance.nonDiscountable,
  'position': instance.position,
  'price_is_indicative': instance.priceIsIndicative,
  'price_on_request': instance.priceOnRequest,
  'product_code': instance.productCode,
  'product_id': ?instance.productId,
  'production_remark': ?instance.productionRemark,
  'quantity': instance.quantity,
  'rebate_percent': instance.rebatePercent,
  'unit': instance.unit,
  'vat_rate': instance.vatRate,
};
