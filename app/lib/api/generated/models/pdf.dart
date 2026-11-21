// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'pdf.g.dart';

@JsonSerializable()
class Pdf {
  const Pdf({
    required this.filename,
    required this.language,
    required this.published,
    required this.revision,
  });

  factory Pdf.fromJson(Map<String, Object?> json) => _$PdfFromJson(json);

  final String filename;
  final String language;
  final bool published;
  final int revision;

  Map<String, Object?> toJson() => _$PdfToJson(this);
}
