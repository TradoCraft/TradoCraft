// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceList _$PriceListFromJson(Map<String, dynamic> json) => PriceList(
  code: json['code'] as String,
  id: json['id'] as String,
  itemCount: (json['item_count'] as num).toInt(),
  name: json['name'] as String,
  settings: PriceListSettings.fromJson(
    json['settings'] as Map<String, dynamic>,
  ),
  validFrom: DateTime.parse(json['valid_from'] as String),
  zones: (json['zones'] as List<dynamic>)
      .map((e) => PriceListZone.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$PriceListToJson(PriceList instance) => <String, dynamic>{
  'code': instance.code,
  'id': instance.id,
  'item_count': instance.itemCount,
  'name': instance.name,
  'settings': instance.settings,
  'valid_from': instance.validFrom.toIso8601String(),
  'zones': instance.zones,
};
