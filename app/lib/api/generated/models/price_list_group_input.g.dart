// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_group_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListGroupInput _$PriceListGroupInputFromJson(Map<String, dynamic> json) =>
    PriceListGroupInput(
      title: Map<String, String>.from(json['title'] as Map),
      gapMm: json['gap_mm'] as String?,
      pageBreak: json['page_break'] as bool?,
      parentId: json['parent_id'] as String?,
      showTitle: json['show_title'] as bool?,
      sortOrder: (json['sort_order'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PriceListGroupInputToJson(
  PriceListGroupInput instance,
) => <String, dynamic>{
  'gap_mm': ?instance.gapMm,
  'page_break': ?instance.pageBreak,
  'parent_id': ?instance.parentId,
  'show_title': ?instance.showTitle,
  'sort_order': ?instance.sortOrder,
  'title': instance.title,
};
