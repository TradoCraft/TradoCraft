// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Document _$DocumentFromJson(Map<String, dynamic> json) => Document(
  id: json['id'] as String,
  keywords: (json['keywords'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  kind: json['kind'] as String,
  productCodes: (json['product_codes'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  title: json['title'] as String,
);

Map<String, dynamic> _$DocumentToJson(Document instance) => <String, dynamic>{
  'id': instance.id,
  'keywords': instance.keywords,
  'kind': instance.kind,
  'product_codes': instance.productCodes,
  'title': instance.title,
};
