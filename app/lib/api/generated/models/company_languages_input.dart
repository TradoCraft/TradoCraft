// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'company_languages_input.g.dart';

/// The company's content languages, in the order pickers show them.
@JsonSerializable()
class CompanyLanguagesInput {
  const CompanyLanguagesInput({
    required this.defaultLanguage,
    required this.languages,
  });
  
  factory CompanyLanguagesInput.fromJson(Map<String, Object?> json) => _$CompanyLanguagesInputFromJson(json);
  
  /// The default language; must be one of `languages`.
  @JsonKey(name: 'default_language')
  final String defaultLanguage;

  /// ISO 639-1 codes in display order, 1 to 50, without duplicates.
  final List<String> languages;

  Map<String, Object?> toJson() => _$CompanyLanguagesInputToJson(this);
}
