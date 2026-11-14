// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_match_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductMatchPage _$ProductMatchPageFromJson(Map<String, dynamic> json) =>
    ProductMatchPage(
      counts: StatusCounts.fromJson(json['counts'] as Map<String, dynamic>),
      items: (json['items'] as List<dynamic>)
          .map((e) => ProductMatch.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
    );

Map<String, dynamic> _$ProductMatchPageToJson(ProductMatchPage instance) =>
    <String, dynamic>{
      'counts': instance.counts,
      'items': instance.items,
      'total': instance.total,
    };
