// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'import_file.g.dart';

/// An uploaded file.
@JsonSerializable()
class ImportFile {
  const ImportFile({
    required this.filename,
    required this.format,
    required this.id,
    required this.sheets,
    required this.sizeBytes,
  });
  
  factory ImportFile.fromJson(Map<String, Object?> json) => _$ImportFileFromJson(json);
  
  final String filename;

  /// `csv`, `xlsx` or `ods`, detected from the content.
  final String format;
  final String id;

  /// The sheets of a workbook in order; empty for CSV.
  final List<String> sheets;
  @JsonKey(name: 'size_bytes')
  final int sizeBytes;

  Map<String, Object?> toJson() => _$ImportFileToJson(this);
}
