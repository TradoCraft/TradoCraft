// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_item_update.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListItemUpdate _$PriceListItemUpdateFromJson(Map<String, dynamic> json) =>
    PriceListItemUpdate(
      groupId: json['group_id'] as String,
      description: (json['description'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      hidden: json['hidden'] as bool?,
      indicative: json['indicative'] as bool?,
      net: json['net'] as bool?,
      priceOnRequest: json['price_on_request'] as bool?,
      sortKey: json['sort_key'] as String?,
    );

Map<String, dynamic> _$PriceListItemUpdateToJson(
  PriceListItemUpdate instance,
) => <String, dynamic>{
  'description': ?instance.description,
  'group_id': instance.groupId,
  'hidden': ?instance.hidden,
  'indicative': ?instance.indicative,
  'net': ?instance.net,
  'price_on_request': ?instance.priceOnRequest,
  'sort_key': ?instance.sortKey,
};
