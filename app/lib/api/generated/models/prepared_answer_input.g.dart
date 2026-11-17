// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prepared_answer_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PreparedAnswerInput _$PreparedAnswerInputFromJson(Map<String, dynamic> json) =>
    PreparedAnswerInput(
      code: json['code'] as String,
      name: json['name'] as String,
      texts: (json['texts'] as List<dynamic>)
          .map((e) => AnswerText.fromJson(e as Map<String, dynamic>))
          .toList(),
      active: json['active'] as bool?,
      category: json['category'] as String?,
      keywords: (json['keywords'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      kind: json['kind'] as String?,
      teamId: json['team_id'] as String?,
    );

Map<String, dynamic> _$PreparedAnswerInputToJson(
  PreparedAnswerInput instance,
) => <String, dynamic>{
  'active': ?instance.active,
  'category': ?instance.category,
  'code': instance.code,
  'keywords': ?instance.keywords,
  'kind': ?instance.kind,
  'name': instance.name,
  'team_id': ?instance.teamId,
  'texts': instance.texts,
};
