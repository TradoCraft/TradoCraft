// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_translation.g.dart';

@JsonSerializable()
class ProductTranslation {
  const ProductTranslation({
    required this.language,
    required this.name,
    this.description,
  });
  
  factory ProductTranslation.fromJson(Map<String, Object?> json) => _$ProductTranslationFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? description;

  /// ISO 639-1 code in lower case, e.g. `nl`, `fr`, `de`.
  final String language;
  final String name;

  Map<String, Object?> toJson() => _$ProductTranslationToJson(this);
}
