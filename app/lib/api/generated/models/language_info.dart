// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'language_info.g.dart';

/// An ISO 639-1 language with its display names.
@JsonSerializable()
class LanguageInfo {
  const LanguageInfo({
    required this.code,
    required this.englishName,
    required this.name,
  });
  
  factory LanguageInfo.fromJson(Map<String, Object?> json) => _$LanguageInfoFromJson(json);
  
  /// ISO 639-1 code, e.g. `pt`.
  final String code;

  /// English name, e.g. `Portuguese`.
  @JsonKey(name: 'english_name')
  final String englishName;

  /// The language's own name, e.g. `Português`.
  final String name;

  Map<String, Object?> toJson() => _$LanguageInfoToJson(this);
}
