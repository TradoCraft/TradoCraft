// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_export.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListExport _$PriceListExportFromJson(Map<String, dynamic> json) =>
    PriceListExport(
      code: json['code'] as String,
      groupIds: (json['group_ids'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: (json['sort_order'] as num).toInt(),
      fileName: json['file_name'] as String?,
    );

Map<String, dynamic> _$PriceListExportToJson(PriceListExport instance) =>
    <String, dynamic>{
      'code': instance.code,
      'file_name': ?instance.fileName,
      'group_ids': instance.groupIds,
      'id': instance.id,
      'name': instance.name,
      'sort_order': instance.sortOrder,
    };
