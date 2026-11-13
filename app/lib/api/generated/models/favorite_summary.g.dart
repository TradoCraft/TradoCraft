// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FavoriteSummary _$FavoriteSummaryFromJson(Map<String, dynamic> json) =>
    FavoriteSummary(
      id: json['id'] as String,
      languages: (json['languages'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      mainProductActive: json['main_product_active'] as bool,
      mainProductCode: json['main_product_code'] as String,
      mainProductId: json['main_product_id'] as String,
      mainProductName: json['main_product_name'] as String,
      name: json['name'] as String,
      optionCount: (json['option_count'] as num).toInt(),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$FavoriteSummaryToJson(FavoriteSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'languages': instance.languages,
      'main_product_active': instance.mainProductActive,
      'main_product_code': instance.mainProductCode,
      'main_product_id': instance.mainProductId,
      'main_product_name': instance.mainProductName,
      'name': instance.name,
      'option_count': instance.optionCount,
      'updated_at': instance.updatedAt.toIso8601String(),
    };
