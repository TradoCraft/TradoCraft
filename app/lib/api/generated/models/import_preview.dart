// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'import_preview.g.dart';

/// The start of a file as the person will see it.
@JsonSerializable()
class ImportPreview {
  const ImportPreview({
    required this.columns,
    required this.format,
    required this.headerRow,
    required this.rowCount,
    required this.rows,
    required this.sheets,
    this.sheet,
  });
  
  factory ImportPreview.fromJson(Map<String, Object?> json) => _$ImportPreviewFromJson(json);
  
  /// The header cells as written.
  final List<String> columns;
  final String format;

  /// The row of the header in the file.
  @JsonKey(name: 'header_row')
  final int headerRow;

  /// Data rows in the file.
  @JsonKey(name: 'row_count')
  final int rowCount;

  /// The first 20 data rows as text, in header order.
  final List<List<String>> rows;

  /// The sheet that was read; null for CSV.
  @JsonKey(includeIfNull: false)
  final String? sheet;
  final List<String> sheets;

  Map<String, Object?> toJson() => _$ImportPreviewToJson(this);
}
