// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportPreview _$ImportPreviewFromJson(
  Map<String, dynamic> json,
) => ImportPreview(
  columns: (json['columns'] as List<dynamic>).map((e) => e as String).toList(),
  format: json['format'] as String,
  headerRow: (json['header_row'] as num).toInt(),
  rowCount: (json['row_count'] as num).toInt(),
  rows: (json['rows'] as List<dynamic>)
      .map((e) => (e as List<dynamic>).map((e) => e as String).toList())
      .toList(),
  sheets: (json['sheets'] as List<dynamic>).map((e) => e as String).toList(),
  sheet: json['sheet'] as String?,
);

Map<String, dynamic> _$ImportPreviewToJson(ImportPreview instance) =>
    <String, dynamic>{
      'columns': instance.columns,
      'format': instance.format,
      'header_row': instance.headerRow,
      'row_count': instance.rowCount,
      'rows': instance.rows,
      'sheet': ?instance.sheet,
      'sheets': instance.sheets,
    };
