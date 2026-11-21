// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'document.dart';
import 'pdf.dart';

part 'document_detail.g.dart';

@JsonSerializable()
class DocumentDetail {
  const DocumentDetail({
    required this.document,
    required this.pdfs,
  });
  
  factory DocumentDetail.fromJson(Map<String, Object?> json) => _$DocumentDetailFromJson(json);
  
  final Document document;
  final List<Pdf> pdfs;

  Map<String, Object?> toJson() => _$DocumentDetailToJson(this);
}
