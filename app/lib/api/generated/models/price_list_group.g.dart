// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListGroup _$PriceListGroupFromJson(Map<String, dynamic> json) =>
    PriceListGroup(
      gapMm: json['gap_mm'] as String,
      id: json['id'] as String,
      pageBreak: json['page_break'] as bool,
      showTitle: json['show_title'] as bool,
      sortOrder: (json['sort_order'] as num).toInt(),
      title: Map<String, String>.from(json['title'] as Map),
      parentId: json['parent_id'] as String?,
    );

Map<String, dynamic> _$PriceListGroupToJson(PriceListGroup instance) =>
    <String, dynamic>{
      'gap_mm': instance.gapMm,
      'id': instance.id,
      'page_break': instance.pageBreak,
      'parent_id': ?instance.parentId,
      'show_title': instance.showTitle,
      'sort_order': instance.sortOrder,
      'title': instance.title,
    };
