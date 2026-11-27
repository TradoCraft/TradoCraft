// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'catalogue_info.g.dart';

/// A language that has a catalogue in a domain.
@JsonSerializable()
class CatalogueInfo {
  const CatalogueInfo({
    required this.companyEntries,
    required this.language,
    required this.shipped,
    this.updatedAt,
  });
  
  factory CatalogueInfo.fromJson(Map<String, Object?> json) => _$CatalogueInfoFromJson(json);
  
  /// Number of texts the company added or overrides.
  @JsonKey(name: 'company_entries')
  final int companyEntries;
  final String language;

  /// The application ships texts in this language.
  final bool shipped;

  /// When the company's texts last changed; none without company texts.
  @JsonKey(includeIfNull: false,name: 'updated_at')
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => _$CatalogueInfoToJson(this);
}
