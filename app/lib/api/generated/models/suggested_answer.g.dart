// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'suggested_answer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SuggestedAnswer _$SuggestedAnswerFromJson(Map<String, dynamic> json) =>
    SuggestedAnswer(
      answerId: json['answer_id'] as String,
      body: json['body'] as String,
      code: json['code'] as String,
      fallback: json['fallback'] as bool,
      kind: json['kind'] as String,
      language: json['language'] as String,
      name: json['name'] as String,
      score: (json['score'] as num).toInt(),
      subject: json['subject'] as String,
      teamId: json['team_id'] as String?,
    );

Map<String, dynamic> _$SuggestedAnswerToJson(SuggestedAnswer instance) =>
    <String, dynamic>{
      'answer_id': instance.answerId,
      'body': instance.body,
      'code': instance.code,
      'fallback': instance.fallback,
      'kind': instance.kind,
      'language': instance.language,
      'name': instance.name,
      'score': instance.score,
      'subject': instance.subject,
      'team_id': ?instance.teamId,
    };
