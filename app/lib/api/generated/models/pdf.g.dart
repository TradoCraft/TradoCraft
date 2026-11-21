// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pdf.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Pdf _$PdfFromJson(Map<String, dynamic> json) => Pdf(
  filename: json['filename'] as String,
  language: json['language'] as String,
  published: json['published'] as bool,
  revision: (json['revision'] as num).toInt(),
);

Map<String, dynamic> _$PdfToJson(Pdf instance) => <String, dynamic>{
  'filename': instance.filename,
  'language': instance.language,
  'published': instance.published,
  'revision': instance.revision,
};
