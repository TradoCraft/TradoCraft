// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DocumentInput _$DocumentInputFromJson(Map<String, dynamic> json) =>
    DocumentInput(
      kind: json['kind'] as String,
      title: json['title'] as String,
      keywords: (json['keywords'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      productCodes: (json['product_codes'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$DocumentInputToJson(DocumentInput instance) =>
    <String, dynamic>{
      'keywords': ?instance.keywords,
      'kind': instance.kind,
      'product_codes': ?instance.productCodes,
      'title': instance.title,
    };
