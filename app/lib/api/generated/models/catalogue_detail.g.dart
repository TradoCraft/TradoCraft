// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalogue_detail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CatalogueDetail _$CatalogueDetailFromJson(Map<String, dynamic> json) =>
    CatalogueDetail(
      domain: Domain.fromJson(json['domain'] as String),
      entries: Map<String, String>.from(json['entries'] as Map),
      language: json['language'] as String,
      shipped: Map<String, String>.from(json['shipped'] as Map),
      source: Map<String, String>.from(json['source'] as Map),
    );

Map<String, dynamic> _$CatalogueDetailToJson(CatalogueDetail instance) =>
    <String, dynamic>{
      'domain': instance.domain,
      'entries': instance.entries,
      'language': instance.language,
      'shipped': instance.shipped,
      'source': instance.source,
    };
