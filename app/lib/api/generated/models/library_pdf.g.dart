// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_pdf.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LibraryPdf _$LibraryPdfFromJson(Map<String, dynamic> json) => LibraryPdf(
  documentId: json['document_id'] as String,
  language: json['language'] as String,
  revision: (json['revision'] as num).toInt(),
);

Map<String, dynamic> _$LibraryPdfToJson(LibraryPdf instance) =>
    <String, dynamic>{
      'document_id': instance.documentId,
      'language': instance.language,
      'revision': instance.revision,
    };
