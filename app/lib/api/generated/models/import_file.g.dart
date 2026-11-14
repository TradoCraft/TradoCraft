// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportFile _$ImportFileFromJson(Map<String, dynamic> json) => ImportFile(
  filename: json['filename'] as String,
  format: json['format'] as String,
  id: json['id'] as String,
  sheets: (json['sheets'] as List<dynamic>).map((e) => e as String).toList(),
  sizeBytes: (json['size_bytes'] as num).toInt(),
);

Map<String, dynamic> _$ImportFileToJson(ImportFile instance) =>
    <String, dynamic>{
      'filename': instance.filename,
      'format': instance.format,
      'id': instance.id,
      'sheets': instance.sheets,
      'size_bytes': instance.sizeBytes,
    };
