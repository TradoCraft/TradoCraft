// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'catalogue_input.g.dart';

/// The texts a company adds or overrides in one domain and language.
@JsonSerializable()
class CatalogueInput {
  const CatalogueInput({
    required this.entries,
  });
  
  factory CatalogueInput.fromJson(Map<String, Object?> json) => _$CatalogueInputFromJson(json);
  
  /// `key → text`; empty texts are dropped. For documents and mail the keys must exist in the.
  /// English source.
  final Map<String, String> entries;

  Map<String, Object?> toJson() => _$CatalogueInputToJson(this);
}
