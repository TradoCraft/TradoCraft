// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rendered_answer.g.dart';

@JsonSerializable()
class RenderedAnswer {
  const RenderedAnswer({
    required this.answerId,
    required this.body,
    required this.fallback,
    required this.language,
    required this.subject,
  });
  
  factory RenderedAnswer.fromJson(Map<String, Object?> json) => _$RenderedAnswerFromJson(json);
  
  @JsonKey(name: 'answer_id')
  final String answerId;
  final String body;

  /// True when no text exists in the ticket's language and another language was used.
  final bool fallback;

  /// Language of the text used.
  final String language;
  final String subject;

  Map<String, Object?> toJson() => _$RenderedAnswerToJson(this);
}
