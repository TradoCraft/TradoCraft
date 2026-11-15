// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListInput _$PriceListInputFromJson(Map<String, dynamic> json) =>
    PriceListInput(
      code: json['code'] as String,
      name: json['name'] as String,
      validFrom: DateTime.parse(json['valid_from'] as String),
      settings: json['settings'] == null
          ? null
          : PriceListSettings.fromJson(
              json['settings'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$PriceListInputToJson(PriceListInput instance) =>
    <String, dynamic>{
      'code': instance.code,
      'name': instance.name,
      'settings': ?instance.settings,
      'valid_from': instance.validFrom.toIso8601String(),
    };
