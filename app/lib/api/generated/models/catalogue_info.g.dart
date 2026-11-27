// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalogue_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CatalogueInfo _$CatalogueInfoFromJson(Map<String, dynamic> json) =>
    CatalogueInfo(
      companyEntries: (json['company_entries'] as num).toInt(),
      language: json['language'] as String,
      shipped: json['shipped'] as bool,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$CatalogueInfoToJson(CatalogueInfo instance) =>
    <String, dynamic>{
      'company_entries': instance.companyEntries,
      'language': instance.language,
      'shipped': instance.shipped,
      'updated_at': ?instance.updatedAt?.toIso8601String(),
    };
