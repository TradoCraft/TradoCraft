// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prepared_answer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PreparedAnswer _$PreparedAnswerFromJson(Map<String, dynamic> json) =>
    PreparedAnswer(
      active: json['active'] as bool,
      code: json['code'] as String,
      id: json['id'] as String,
      keywords: (json['keywords'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      kind: json['kind'] as String,
      name: json['name'] as String,
      texts: (json['texts'] as List<dynamic>)
          .map((e) => AnswerText.fromJson(e as Map<String, dynamic>))
          .toList(),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      category: json['category'] as String?,
      teamId: json['team_id'] as String?,
    );

Map<String, dynamic> _$PreparedAnswerToJson(PreparedAnswer instance) =>
    <String, dynamic>{
      'active': instance.active,
      'category': ?instance.category,
      'code': instance.code,
      'id': instance.id,
      'keywords': instance.keywords,
      'kind': instance.kind,
      'name': instance.name,
      'team_id': ?instance.teamId,
      'texts': instance.texts,
      'updated_at': instance.updatedAt.toIso8601String(),
    };
