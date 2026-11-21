// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'library_pdf.g.dart';

/// The exact published library variant selected by the agent.
@JsonSerializable()
class LibraryPdf {
  const LibraryPdf({
    required this.documentId,
    required this.language,
    required this.revision,
  });
  
  factory LibraryPdf.fromJson(Map<String, Object?> json) => _$LibraryPdfFromJson(json);
  
  @JsonKey(name: 'document_id')
  final String documentId;
  final String language;
  final int revision;

  Map<String, Object?> toJson() => _$LibraryPdfToJson(this);
}
