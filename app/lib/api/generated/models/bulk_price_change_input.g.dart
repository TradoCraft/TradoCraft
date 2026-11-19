// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bulk_price_change_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BulkPriceChangeInput _$BulkPriceChangeInputFromJson(
  Map<String, dynamic> json,
) => BulkPriceChangeInput(
  kind: ChangeKind.fromJson(json['kind'] as String),
  validFrom: DateTime.parse(json['valid_from'] as String),
  value: json['value'] as String,
  familyId: json['family_id'] as String?,
  productIds: (json['product_ids'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  replacePlanned: json['replace_planned'] as bool?,
  rounding: json['rounding'] as String?,
  zoneIds: (json['zone_ids'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$BulkPriceChangeInputToJson(
  BulkPriceChangeInput instance,
) => <String, dynamic>{
  'family_id': ?instance.familyId,
  'kind': instance.kind,
  'product_ids': ?instance.productIds,
  'replace_planned': ?instance.replacePlanned,
  'rounding': ?instance.rounding,
  'valid_from': instance.validFrom.toIso8601String(),
  'value': instance.value,
  'zone_ids': ?instance.zoneIds,
};
