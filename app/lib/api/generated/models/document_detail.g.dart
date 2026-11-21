// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document_detail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DocumentDetail _$DocumentDetailFromJson(Map<String, dynamic> json) =>
    DocumentDetail(
      document: Document.fromJson(json['document'] as Map<String, dynamic>),
      pdfs: (json['pdfs'] as List<dynamic>)
          .map((e) => Pdf.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DocumentDetailToJson(DocumentDetail instance) =>
    <String, dynamic>{'document': instance.document, 'pdfs': instance.pdfs};
