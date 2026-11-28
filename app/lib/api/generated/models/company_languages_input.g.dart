// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company_languages_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CompanyLanguagesInput _$CompanyLanguagesInputFromJson(
  Map<String, dynamic> json,
) => CompanyLanguagesInput(
  defaultLanguage: json['default_language'] as String,
  languages: (json['languages'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$CompanyLanguagesInputToJson(
  CompanyLanguagesInput instance,
) => <String, dynamic>{
  'default_language': instance.defaultLanguage,
  'languages': instance.languages,
};
