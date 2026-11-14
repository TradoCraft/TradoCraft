// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quotation_line_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

QuotationLineInput _$QuotationLineInputFromJson(Map<String, dynamic> json) =>
    QuotationLineInput(
      productId: json['product_id'] as String,
      quantity: json['quantity'] as String,
      addOptions: json['add_options'] as bool?,
      comment: json['comment'] as String?,
      customerRemark: json['customer_remark'] as String?,
      customerRemarkLanguage: json['customer_remark_language'] as String?,
      description: json['description'] as String?,
      favoriteItemId: json['favorite_item_id'] as String?,
      lineDiscountPercent: json['line_discount_percent'] as String?,
      parentPosition: (json['parent_position'] as num?)?.toInt(),
      percentBase: json['percent_base'] == null
          ? null
          : PercentBase.fromJson(json['percent_base'] as String),
      percentOfParent: json['percent_of_parent'] as String?,
      productionRemark: json['production_remark'] as String?,
      section: json['section'] as String?,
      unitPrice: json['unit_price'] as String?,
    );

Map<String, dynamic> _$QuotationLineInputToJson(QuotationLineInput instance) =>
    <String, dynamic>{
      'add_options': ?instance.addOptions,
      'comment': ?instance.comment,
      'customer_remark': ?instance.customerRemark,
      'customer_remark_language': ?instance.customerRemarkLanguage,
      'description': ?instance.description,
      'favorite_item_id': ?instance.favoriteItemId,
      'line_discount_percent': ?instance.lineDiscountPercent,
      'parent_position': ?instance.parentPosition,
      'percent_base': ?instance.percentBase,
      'percent_of_parent': ?instance.percentOfParent,
      'product_id': instance.productId,
      'production_remark': ?instance.productionRemark,
      'quantity': instance.quantity,
      'section': ?instance.section,
      'unit_price': ?instance.unitPrice,
    };
