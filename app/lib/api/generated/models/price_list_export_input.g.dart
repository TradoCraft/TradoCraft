// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_export_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListExportInput _$PriceListExportInputFromJson(
  Map<String, dynamic> json,
) => PriceListExportInput(
  code: json['code'] as String,
  name: json['name'] as String,
  fileName: json['file_name'] as String?,
  groupIds: (json['group_ids'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  sortOrder: (json['sort_order'] as num?)?.toInt(),
);

Map<String, dynamic> _$PriceListExportInputToJson(
  PriceListExportInput instance,
) => <String, dynamic>{
  'code': instance.code,
  'file_name': ?instance.fileName,
  'group_ids': ?instance.groupIds,
  'name': instance.name,
  'sort_order': ?instance.sortOrder,
};
