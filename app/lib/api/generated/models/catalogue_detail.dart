// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'domain.dart';

part 'catalogue_detail.g.dart';

/// One catalogue: the company's texts, the shipped texts and the English source.
@JsonSerializable()
class CatalogueDetail {
  const CatalogueDetail({
    required this.domain,
    required this.entries,
    required this.language,
    required this.shipped,
    required this.source,
  });
  
  factory CatalogueDetail.fromJson(Map<String, Object?> json) => _$CatalogueDetailFromJson(json);
  
  final Domain domain;

  /// Texts the company added or overrides.
  final Map<String, String> entries;
  final String language;

  /// Texts the application ships in this language (documents and mail only).
  final Map<String, String> shipped;

  /// The English source texts: every key there is, the template for a translator (documents.
  /// and mail only; the clients ship their own source for app and web).
  final Map<String, String> source;

  Map<String, Object?> toJson() => _$CatalogueDetailToJson(this);
}
