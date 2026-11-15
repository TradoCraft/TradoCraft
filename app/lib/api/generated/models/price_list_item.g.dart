// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListItem _$PriceListItemFromJson(Map<String, dynamic> json) =>
    PriceListItem(
      description: Map<String, String>.from(json['description'] as Map),
      groupId: json['group_id'] as String,
      hidden: json['hidden'] as bool,
      id: json['id'] as String,
      indicative: json['indicative'] as bool,
      net: json['net'] as bool,
      priceOnRequest: json['price_on_request'] as bool,
      productCode: json['product_code'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      sortKey: json['sort_key'] as String,
    );

Map<String, dynamic> _$PriceListItemToJson(PriceListItem instance) =>
    <String, dynamic>{
      'description': instance.description,
      'group_id': instance.groupId,
      'hidden': instance.hidden,
      'id': instance.id,
      'indicative': instance.indicative,
      'net': instance.net,
      'price_on_request': instance.priceOnRequest,
      'product_code': instance.productCode,
      'product_id': instance.productId,
      'product_name': instance.productName,
      'sort_key': instance.sortKey,
    };
