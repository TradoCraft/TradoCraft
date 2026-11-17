// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'suggested_answer.g.dart';

@JsonSerializable()
class SuggestedAnswer {
  const SuggestedAnswer({
    required this.answerId,
    required this.body,
    required this.code,
    required this.fallback,
    required this.kind,
    required this.language,
    required this.name,
    required this.score,
    required this.subject,
    this.teamId,
  });
  
  factory SuggestedAnswer.fromJson(Map<String, Object?> json) => _$SuggestedAnswerFromJson(json);
  
  @JsonKey(name: 'answer_id')
  final String answerId;
  final String body;
  final String code;
  final bool fallback;
  final String kind;

  /// Language of the text used.
  final String language;
  final String name;
  final int score;
  final String subject;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;

  Map<String, Object?> toJson() => _$SuggestedAnswerToJson(this);
}
